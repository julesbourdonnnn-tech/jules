/*
 * ============================================================
 *  GUIDES THÉMATIQUES (pages « guides/<slug>.html »)
 * ============================================================
 *  Chaque guide sélectionne automatiquement les établissements de
 *  js/hotels.js qui correspondent à son thème (match) ou une liste
 *  choisie à la main (ids). Les titres s'adaptent au nombre d'adresses.
 *  cat : "envie" | "lieu" | "region" | "trajet" | "ville" (rubrique de la page des guides).
 *  min : nombre minimum d'adresses pour publier le guide (sinon il est masqué).
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
  const hasTag = (t) => (h) => (h.tags || []).includes(t);

  // « Le coup de cœur du moment » : même règle que isCoupDeCoeur (js/core.js)
  const coupDeCoeur = (h) => !!h.coupDeCoeur;

  global.GUIDES = [
    {
      slug: "coups-de-coeur-de-jules",
      cat: "envie",
      kicker: "Coup de cœur du moment",
      short: "Le coup de cœur du moment",
      title: (n) => `Le coup de cœur du moment : ${n} adresses qui m'ont marqué`,
      description: "La sélection du moment de Jules Bourdon, fondateur de Nuits Singulières et professionnel de l'hôtellerie : ses adresses préférées du moment, testées ou repérées, sans commission ni contrepartie.",
      match: coupDeCoeur,
      sort: (a, b) => (b.review ? 1 : 0) - (a.review ? 1 : 0),
      intro: [
        "Voici mes adresses préférées du moment. Celles que j'ai testées, je les recommande en connaissance de cause : vous trouverez mon avis complet sur leur fiche. Les autres sont mes repérages les plus marquants, des lieux si singuliers que j'ai hâte d'y dormir ; elles sont signalées « Repérage ».",
        "Cette sélection change au fil des saisons et de mes séjours. Elle ne s'achète pas : aucun établissement ne paie pour y figurer, et une invitation n'y donne aucun droit.",
      ],
      faq: [
        ["Comment un hôtel entre-t-il dans le coup de cœur du moment ?", "C'est un choix personnel : un lieu vraiment singulier, qui m'a marqué, au moment où je le choisis. Les adresses testées portent le badge « Testé » et mon avis détaillé ; les autres sont clairement signalées comme des repérages, où je n'ai pas encore séjourné."],
        ["Un hôtel peut-il payer pour figurer dans cette sélection ?", "Non. Aucun établissement ne paie pour être présenté ou distingué. Quand un séjour m'a été offert, je l'indique clairement sur l'avis, et cela ne change rien à mon jugement."],
      ],
      tips: [
        "Pour les adresses testées, lisez l'avis complet : le conseil du pro vous dit quelle chambre demander et quand venir.",
        "Une question précise sur l'une de ces adresses ? Posez-la en bas de sa fiche : je vous réponds personnellement.",
      ],
    },
    {
      slug: "nuit-insolite-en-amoureux",
      cat: "envie",
      kicker: "En amoureux",
      short: "Nuits insolites en amoureux",
      title: (n) => `${n} nuits insolites pour un week-end en amoureux`,
      description: "Bulle sous les étoiles, phare, cabane avec jacuzzi, jardin secret à Montmartre : ma sélection d'hébergements insolites pour une escapade à deux en France.",
      ids: ["attrap-reves-allauch", "phare-de-kerbel", "loire-valley-lodges", "pella-roca", "hotel-particulier-montmartre", "les-roches-rouges", "la-coorniche", "alpinest", "cabanes-du-moulin", "les-hautes-roches", "bulles-de-savoie", "ecrin-d-auvergne"],
      cover: "phare-de-kerbel",
      intro: [
        "Pour un anniversaire, une demande en mariage ou simplement deux jours rien qu'à deux, rien ne vaut un lieu qui sort de l'ordinaire. J'ai rassemblé ici mes adresses les plus romantiques : on s'y endort sous les étoiles, au sommet d'un phare ou dans les arbres, loin de tout.",
        "Elles cultivent toutes l'intimité, avec un décor qu'on n'oublie pas ; plusieurs offrent un spa ou un jacuzzi privatif.",
      ],
      faq: [
        ["Quelle est la nuit insolite la plus romantique de France ?", "Tout dépend de vos envies : une bulle transparente pour s'endormir sous les étoiles, le sommet d'un phare face à l'océan, ou une cabane perchée avec jacuzzi privatif. Les adresses de ce guide ont toutes été choisies pour leur intimité."],
        ["Combien coûte une nuit insolite en amoureux ?", "Comptez généralement de 150 à 450 € la nuit pour deux selon le lieu et la saison. Chaque fiche indique une fourchette de prix, et le tarif exact est donné sur le site officiel de l'établissement."],
        ["Quand réserver pour la Saint-Valentin ?", "Le plus tôt possible, idéalement un à deux mois avant : ces lieux comptent souvent très peu de chambres ou de cabanes, et les dates clés partent en premier."],
      ],
      tips: [
        "Réservez tôt pour les dates clés (Saint-Valentin, ponts de mai, week-ends d'été) : ces lieux comptent souvent très peu de chambres.",
        "Demandez à l'établissement s'il propose des attentions à ajouter à la réservation (bouteille, fleurs, dîner livré, massage).",
        "Vérifiez les heures d'arrivée : certains lieux isolés demandent d'arriver avant la nuit.",
      ],
    },
    {
      slug: "cabanes-perchees",
      cat: "lieu",
      kicker: "Cabanes perchées",
      short: "Les plus belles cabanes perchées",
      title: (n) => `Les ${n} plus belles cabanes perchées de France`,
      description: "Cabanes dans les arbres avec jacuzzi, cabanes d'artistes, cabanes flottantes : ma sélection des plus belles cabanes perchées où dormir en France.",
      match: (h) => h.type === "cabane",
      cover: "loire-valley-lodges",
      intro: [
        "Dormir dans les arbres, c'est retrouver ses rêves d'enfant avec le confort d'aujourd'hui. Les cabanes de ma sélection vont de l'adresse bohème au véritable hôtel de luxe perché, avec baies vitrées, jacuzzi privatif et dîner livré à la cabane.",
        "On y accède par des escaliers, des passerelles suspendues ou des échelles, puis la forêt fait le reste : le chant des oiseaux au réveil, le vent dans les branches, et le silence.",
      ],
      faq: [
        ["Peut-on dormir dans une cabane perchée toute l'année ?", "Beaucoup de cabanes de ce guide sont chauffées et ouvertes une grande partie de l'année : vérifiez les dates d'ouverture au moment de réserver. Celles qui ont un bain nordique ou un jacuzzi privatif sont particulièrement agréables en automne et en hiver."],
        ["Les cabanes perchées conviennent-elles aux enfants ?", "Certaines oui, d'autres sont réservées aux couples ou demandent un âge minimum à cause des escaliers et des passerelles. Vérifiez les conditions sur la fiche et au moment de réserver."],
        ["Combien coûte une nuit en cabane perchée ?", "De moins de 150 € pour les cabanes les plus simples à plus de 250 € pour les cabanes-spa avec jacuzzi et dîner livré, pour deux personnes."],
      ],
      tips: [
        "Vérifiez l'accès : certaines cabanes se rejoignent par des passerelles ou des échelles, peu pratiques avec de gros bagages ou de très jeunes enfants.",
        "Pour profiter d'un bain nordique ou d'un jacuzzi en plein air, les nuits de printemps et d'automne sont idéales.",
        "Emportez une lampe frontale et des chaussures confortables : les chemins de forêt sont peu éclairés la nuit.",
      ],
    },
    {
      slug: "week-end-insolite-pres-de-paris",
      cat: "region",
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
      faq: [
        ["Où passer un week-end insolite près de Paris ?", "Les adresses de ce guide sont classées de la plus proche à la plus éloignée de Paris : cabanes au bord de la rivière en Seine-et-Marne, hôtels troglodytes et abbaye royale en vallée de la Loire, château en Bourgogne…"],
        ["Peut-on y aller en train ?", "Plusieurs adresses de la vallée de la Loire sont proches des gares de Tours ou de Saumur. Consultez aussi mon guide des nuits insolites accessibles sans voiture."],
      ],
      tips: [
        "Partez le vendredi en fin de matinée ou le samedi tôt pour éviter les bouchons de sortie de Paris.",
        "La vallée de la Loire est aussi accessible en train : pensez-y pour les adresses proches de Tours ou de Saumur.",
        "Combinez votre nuit avec une visite : les châteaux de la Loire et le Mont-Saint-Michel sont à deux pas de plusieurs de ces adresses.",
      ],
    },
    {
      slug: "hotels-troglodytes",
      cat: "lieu",
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
      cat: "envie",
      kicker: "Spa privatif",
      short: "Nuits insolites avec spa privatif",
      title: (n) => `${n} nuits insolites avec spa ou jacuzzi privatif`,
      description: "Cabanes perchées avec jacuzzi, sauna privatif, spa en pleine forêt : les hébergements insolites où l'on profite d'un bain chaud rien qu'à deux.",
      match: (h) => (h.tags || []).includes("spa-prive") || h.amenities.some((a) => /privati/i.test(a) && /(spa|jacuzzi|sauna|bain)/i.test(a)),
      cover: "pella-roca",
      intro: [
        "Un bain chaud sous les arbres, un sauna face à la vallée, un jacuzzi sur sa terrasse perchée : ces adresses offrent un espace bien-être rien que pour vous, sans horaires ni voisins.",
        "C'est l'une des expériences les plus recherchées pour une nuit insolite, à réserver en priorité pour les saisons fraîches.",
      ],
      faq: [
        ["Qu'est-ce qu'un spa privatif ?", "C'est un jacuzzi, un sauna ou un bain nordique réservé à votre seul hébergement, souvent sur la terrasse : vous en profitez à toute heure, sans croiser personne."],
        ["Le bain nordique est-il chauffé en hiver ?", "Oui : les bains nordiques sont chauffés au feu de bois ou à l'électricité, et c'est justement l'hiver qu'ils sont les plus magiques, sous la neige ou les étoiles."],
      ],
      tips: [
        "Le bain est souvent chauffé en permanence : pensez à demander l'heure à laquelle il est prêt à votre arrivée.",
        "Emportez un peignoir léger ou des sandales si l'établissement ne les fournit pas.",
        "Hydratez-vous bien : chaleur et bulles se marient bien avec une bonne bouteille d'eau.",
      ],
    },
    {
      slug: "hotels-insolites-bord-de-mer",
      cat: "lieu",
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
      cat: "lieu",
      kicker: "Montagne",
      short: "Hôtels insolites à la montagne",
      title: (n) => `${n} hôtels insolites à la montagne`,
      description: "L'hôtel le plus haut de France, un village d'igloos, des cabanes-spa et un hameau de fermes d'alpage : mes hébergements insolites à la montagne.",
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
      cat: "lieu",
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
      cat: "region",
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
      cat: "lieu",
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
      cat: "envie",
      kicker: "Petits budgets",
      short: "Nuits insolites à petit prix",
      title: (n) => `${n} nuits insolites pour moins de 250 € la nuit`,
      description: "Troglodytes, cabanes, bulle, hôtel Le Corbusier : les hébergements insolites de ma sélection à moins de 250 € la nuit (budget indicatif).",
      match: (h) => h.budget <= 2,
      sort: (a, b) => a.budget - b.budget,
      cover: "hotel-le-corbusier",
      intro: [
        "Une nuit extraordinaire n'est pas forcément hors de prix. Toutes les adresses de ce guide ont un budget indicatif inférieur à 250 € la nuit pour deux, et plusieurs sont sous la barre des 150 €.",
        "Les prix varient selon la saison, le jour de la semaine et le type de chambre : vérifiez toujours le tarif exact pour vos dates.",
      ],
      faq: [
        ["Peut-on vivre une nuit insolite pour moins de 150 € ?", "Oui : cabanes sur l'eau qu'on rejoint en canoë, wagon-lit de 1926, chambres troglodytes ou hôtel dans la Cité radieuse de Le Corbusier, plusieurs adresses de ce guide sont sous les 150 € la nuit pour deux."],
        ["Comment payer moins cher une nuit insolite ?", "Privilégiez la semaine et les ailes de saison (printemps, automne), réservez tôt, et comparez les dates directement depuis la fiche du lieu."],
      ],
      tips: [
        "Les nuits en semaine et hors vacances scolaires sont souvent nettement moins chères.",
        "Comparez les types de chambres : la différence de prix peut être importante au sein d'un même établissement.",
        "Regardez ce qui est inclus (petit-déjeuner, dîner, activités) avant de comparer les tarifs.",
      ],
    },
    {
      slug: "hotels-insolites-paris",
      cat: "region",
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
      cat: "lieu",
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
    /* ---------- Envies et occasions ---------- */
    {
      slug: "nuit-insolite-avec-son-chien",
      cat: "envie",
      kicker: "Avec son chien",
      short: "Nuits insolites avec son chien",
      title: (n) => `${n} hôtels d'exception où votre chien est le bienvenu`,
      description: "Châteaux, moulin, hôtel les pieds dans l'eau, chalets de Megève : les lieux extraordinaires de France qui acceptent les chiens, avec les conditions à connaître.",
      match: hasTag("chien"),
      cover: "domaine-des-etangs",
      intro: [
        "Partir sans son chien, c'est souvent la moitié du plaisir en moins. Bonne nouvelle : plusieurs de mes adresses les plus remarquables l'accueillent volontiers, parfois avec gamelle, panier et friandise qui l'attendent dans la chambre.",
        "Châteaux au-dessus de la Dordogne, domaine de 1 000 hectares, hôtel face à la Méditerranée ou chalets au cœur de Megève : de quoi s'offrir un séjour hors du commun, à trois.",
      ],
      tips: [
        "Signalez toujours votre chien au moment de la réservation : un supplément par nuit s'applique souvent, et certains établissements ne l'acceptent que dans certaines chambres.",
        "Les chiens ne sont généralement pas admis au restaurant, au spa ni autour des piscines : prévoyez de quoi l'occuper pendant ces moments.",
        "Emportez son panier, sa gamelle et une serviette : les promenades en forêt ou au bord de l'eau finissent rarement propres.",
      ],
    },
    {
      slug: "nuit-insolite-en-famille",
      cat: "envie",
      kicker: "En famille",
      short: "Nuits insolites en famille",
      title: (n) => `${n} nuits insolites en famille ou entre amis`,
      description: "Phare, île privée, igloo, cabanes sur l'eau, wagon-lit de 1926 : les hébergements insolites de France où l'on peut dormir à 4, 6, 10 personnes ou plus.",
      match: hasTag("famille"),
      cover: "phare-de-kerbel",
      intro: [
        "Les plus beaux souvenirs d'enfance se construisent souvent dans des lieux extraordinaires : une nuit dans un igloo, un phare, une cabane qu'on rejoint en canoë ou le compartiment d'un train de légende.",
        "Toutes les adresses de ce guide accueillent au moins quatre personnes, et plusieurs se privatisent entièrement pour une tribu : parfait pour les vacances en famille, les anniversaires ou les retrouvailles entre amis.",
      ],
      tips: [
        "Vérifiez l'âge minimum : certaines cabanes perchées ou accès en canoë ne conviennent pas aux tout-petits.",
        "Pour les grandes tribus, les lieux qui se privatisent (phare, île, villa) se réservent souvent très longtemps à l'avance.",
        "Emportez des lampes de poche et des jeux de société : sans télévision, les soirées deviennent vite les meilleurs moments.",
      ],
    },
    {
      slug: "nuit-insolite-sans-voiture",
      cat: "envie",
      kicker: "Sans voiture",
      short: "Nuits insolites sans voiture",
      title: (n) => `${n} nuits insolites accessibles en train`,
      description: "Refuge au bord de la Mer de Glace, igloo sur les pistes, Cité de Carcassonne, Mont-Saint-Michel, hôtel flottant : les nuits insolites que l'on rejoint en train et en transports en commun.",
      match: hasTag("train"),
      cover: "refuge-du-montenvers",
      intro: [
        "Pas de voiture ? Aucun problème. Ces adresses extraordinaires se rejoignent en train, puis en métro, en bus, en navette ou même… en petit train à crémaillère, comme le refuge du Montenvers au bord de la Mer de Glace.",
        "Le voyage devient une partie de l'aventure : on arrive reposé, sans chercher de place pour se garer, et l'on repart avec une bonne conscience en prime.",
      ],
      tips: [
        "Achetez vos billets de train tôt : pour les week-ends et les vacances, les prix grimpent vite.",
        "Vérifiez les horaires de la dernière navette ou du dernier bus : dans les stations et sites isolés, ils s'arrêtent parfois tôt le soir.",
        "Voyagez léger : certaines adresses (Mont-Saint-Michel, refuges) se rejoignent à pied avec vos bagages.",
      ],
    },
    {
      slug: "nuit-sous-les-etoiles",
      cat: "lieu",
      kicker: "Sous les étoiles",
      short: "Dormir sous les étoiles",
      title: (n) => `Dormir sous les étoiles : ${n} ${plural(n, "nuit", "nuits")} face au ciel`,
      description: "Bulles transparentes, observatoire du Pic du Midi, bulles étoilées en forêt : les plus belles nuits à la belle étoile, avec le confort d'un vrai lit.",
      ids: ["pic-du-midi", "attrap-reves-allauch", "bulles-de-savoie", "etape-en-foret", "dihan"],
      cover: "bulles-de-savoie",
      intro: [
        "S'endormir en regardant les étoiles filer, sans quitter la chaleur de sa couette : c'est la promesse des bulles transparentes, et de l'observatoire du Pic du Midi, où l'on observe le ciel au télescope à 2 877 mètres.",
        "Loin des lumières des villes, le ciel se révèle comme on l'a rarement vu. Il ne reste plus qu'à choisir une nuit sans lune.",
      ],
      tips: [
        "Consultez le calendrier lunaire : autour de la nouvelle lune, le ciel est bien plus noir et les étoiles bien plus nombreuses.",
        "Les nuits d'août offrent les étoiles filantes des Perséides ; celles de décembre, les Géminides.",
        "Dans une bulle, emportez un masque de sommeil : le soleil vous réveillera très tôt.",
      ],
    },
    {
      slug: "demande-en-mariage-lieu-insolite",
      cat: "envie",
      kicker: "Demande en mariage",
      short: "Où faire sa demande en mariage",
      title: (n) => `Demande en mariage : ${n} lieux insolites pour dire « oui »`,
      description: "Sommet d'un phare, observatoire, bulle sous les étoiles, château au-dessus de la Dordogne : les lieux les plus romantiques de France pour une demande en mariage.",
      ids: ["phare-de-kerbel", "pic-du-midi", "bulles-de-savoie", "chateau-de-la-treyne", "cap-estel", "grand-controle-versailles", "la-coorniche", "pella-roca"],
      cover: "phare-de-kerbel",
      intro: [
        "Il y a des questions qu'on ne pose qu'une fois. Autant choisir un décor à la hauteur : le sommet d'un phare face à l'océan, un observatoire au-dessus des nuages, une bulle sous les étoiles ou un château suspendu au-dessus d'une rivière.",
        "J'ai choisi des lieux où l'intimité est garantie et où le cadre fait déjà la moitié du travail. À vous de trouver les mots.",
      ],
      tips: [
        "Prévenez l'établissement en réservant : beaucoup aiment participer (bouteille au frais, fleurs, table en terrasse, bague glissée au dessert).",
        "Choisissez l'heure : le coucher du soleil reste imbattable pour la lumière et l'émotion.",
        "Prévoyez un plan B en cas de pluie ou de brouillard, surtout en montagne et en bord de mer.",
      ],
    },
    {
      slug: "idee-anniversaire-nuit-insolite",
      cat: "envie",
      kicker: "Anniversaire",
      short: "Fêter un anniversaire autrement",
      title: (n) => `${n} idées de nuit insolite pour un anniversaire`,
      description: "Voiture-lits de 1926, île privée, igloo, cabane sur l'eau, château de Versailles : les idées de nuits insolites pour fêter un anniversaire, à deux ou en tribu.",
      ids: ["ile-louet", "gare-de-guiscriff", "village-igloo-val-thorens", "grand-controle-versailles", "loire-valley-lodges", "cabanes-lacustra", "nids-des-vosges", "hotel-particulier-montmartre", "fontevraud-l-ermitage", "refuge-du-montenvers"],
      cover: "loire-valley-lodges",
      intro: [
        "Pour une date qui compte, un dîner au restaurant ne suffit pas toujours. Offrez plutôt une nuit dont on parlera encore dans dix ans : dans le compartiment d'un train de 1926, sur une île rien que pour vous, dans un igloo ou une cabane qu'on rejoint en canoë.",
        "J'ai mêlé ici des adresses pour deux et des lieux à partager en famille ou entre amis, pour tous les budgets.",
      ],
      tips: [
        "Pour une surprise, réservez à votre nom et ne dévoilez que la date et la tenue à prévoir.",
        "Les lieux qui se privatisent pour un groupe (île, wagon, villa) se réservent souvent plusieurs mois à l'avance.",
        "Demandez si l'établissement peut préparer un gâteau, une bouteille ou une décoration : c'est souvent possible sur demande.",
      ],
    },
    {
      slug: "offrir-une-nuit-insolite",
      cat: "envie",
      kicker: "Idée cadeau",
      short: "Offrir une nuit insolite",
      gift: true,
      title: (n) => `Offrir une nuit insolite : ${n} idées cadeaux inoubliables`,
      description: "Bulle, cabane-spa, phare, observatoire, château : mes idées pour offrir une nuit insolite en France, et comment faire un cadeau réussi (dates, bons cadeaux, coffrets).",
      ids: ["bulles-de-savoie", "pella-roca", "phare-de-kerbel", "pic-du-midi", "loire-valley-lodges", "ecrin-d-auvergne", "toue-cabanee-canal-de-bourgogne", "nids-des-vosges", "hotel-particulier-montmartre", "gare-de-guiscriff"],
      cover: "pella-roca",
      intro: [
        "Saint-Valentin, fête des mères, anniversaire, Noël : une nuit dans un lieu extraordinaire est l'un des cadeaux qui marquent le plus. On n'offre pas un objet, mais un souvenir à vivre.",
        "Voici mes idées les plus sûres, pour tous les budgets, et trois façons d'offrir : réserver des dates, demander un bon cadeau à l'établissement, ou choisir un coffret pour laisser le choix.",
      ],
      tips: [
        "Si vous connaissez les disponibilités de la personne, réservez directement des dates : c'est le cadeau le plus simple et le plus fort.",
        "Sinon, demandez à l'établissement s'il propose un bon cadeau : beaucoup de lieux insolites en vendent, parfois même sur leur site.",
        "Pour laisser le choix du lieu et des dates, un coffret « séjour insolite » est une bonne solution : vérifiez sa durée de validité et les adresses qu'il inclut.",
      ],
    },

    /* ---------- Régions ---------- */
    {
      slug: "hotels-insolites-bretagne",
      cat: "region",
      kicker: "Bretagne",
      short: "Hôtels insolites en Bretagne",
      title: (n) => `Bretagne : ${n} nuits insolites entre phares, îles et forêts`,
      description: "Dormir au sommet d'un phare, sur une île privée de la baie de Morlaix, dans une cabane près de Carnac ou un wagon-lit de 1926 : les hébergements insolites de Bretagne.",
      match: (h) => h.region === "Bretagne",
      cover: "phare-de-kerbel",
      intro: [
        "La Bretagne a le goût des lieux habités par les légendes. On y dort au sommet d'un phare face à la rade de Lorient, dans la maison du gardien d'une île de la baie de Morlaix ou dans un compartiment de train des années folles.",
        "Entre côtes sauvages et forêts de l'intérieur, chaque adresse raconte une histoire, et toutes se prêtent aux longues balades iodées.",
      ],
      tips: [
        "Le temps change vite : emportez toujours un vêtement de pluie, même en plein été.",
        "Pour l'île Louët, les réservations n'ouvrent qu'une fois par an : surveillez les annonces de l'office de tourisme de la baie de Morlaix.",
        "La voie verte n° 7 et la côte se découvrent très bien à vélo : pensez à en louer sur place.",
      ],
    },
    {
      slug: "hotels-insolites-provence-cote-d-azur",
      cat: "region",
      kicker: "Provence & Côte d'Azur",
      short: "Insolite en Provence et sur la Côte d'Azur",
      title: (n) => `Provence et Côte d'Azur : ${n} adresses insolites et solaires`,
      description: "Bulle sous le ciel de Provence, Cité radieuse de Le Corbusier, cabanes-spa, vignoble-musée, hôtels les pieds dans la Méditerranée : les lieux insolites du Sud-Est.",
      match: (h) => h.region === "Provence-Alpes-Côte d'Azur",
      cover: "les-roches-rouges",
      intro: [
        "Sous la lumière du Sud, l'insolite prend mille formes : une bulle transparente au-dessus de Marseille, une chambre dans la Cité radieuse de Le Corbusier, des cabanes-spa entre Alpes et Provence ou une villa au milieu d'un vignoble peuplé d'œuvres d'art.",
        "Et pour les amoureux de la mer, deux adresses posées au ras de la Méditerranée, entre les roches rouges de l'Esterel et la presqu'île d'Èze.",
      ],
      tips: [
        "En juillet et août, réservez très tôt et privilégiez les séjours en semaine : la Côte d'Azur est prise d'assaut.",
        "Le printemps et le début de l'automne offrent une lumière superbe, une mer encore chaude et bien moins de monde.",
        "Pour la Cité radieuse, prenez le temps de visiter le toit-terrasse et les rues intérieures du bâtiment.",
      ],
    },
    {
      slug: "hotels-insolites-occitanie",
      cat: "region",
      kicker: "Occitanie",
      short: "Hôtels insolites en Occitanie",
      title: (n) => `Occitanie : ${n} nuits insolites, du Pic du Midi à Carcassonne`,
      description: "Observatoire du Pic du Midi, Cité médiévale de Carcassonne, châteaux au-dessus du Lot et de la Dordogne, cabanes-spa du Quercy : les lieux insolites d'Occitanie.",
      match: (h) => h.region === "Occitanie",
      cover: "pic-du-midi",
      intro: [
        "De la haute montagne des Pyrénées aux vallées du Lot, l'Occitanie concentre quelques-unes des nuits les plus spectaculaires de France : un observatoire à 2 877 mètres, une Cité médiévale rien que pour soi le soir, des châteaux perchés au-dessus des rivières.",
        "Entre causses, vignobles de Cahors et villages classés, chaque adresse est une porte ouverte sur une région de caractère.",
      ],
      tips: [
        "Pour le Pic du Midi, réservez plusieurs mois à l'avance et vérifiez la météo : le téléphérique peut fermer en cas de vent fort.",
        "Dans le Lot, combinez votre nuit avec Rocamadour, Saint-Cirq-Lapopie et le gouffre de Padirac, tout proches.",
        "À Carcassonne, profitez de la Cité tôt le matin et le soir, quand les visiteurs sont partis.",
      ],
    },
    {
      slug: "hotels-insolites-nouvelle-aquitaine",
      cat: "region",
      kicker: "Sud-Ouest",
      short: "Insolite en Nouvelle-Aquitaine",
      title: (n) => `Nouvelle-Aquitaine : ${n} adresses d'exception, de la dune du Pilat au Périgord`,
      description: "Face à la dune du Pilat, au milieu des grands crus de Bordeaux, dans un château de conte en Charente ou un moulin du Périgord : les lieux d'exception de Nouvelle-Aquitaine.",
      match: (h) => h.region === "Nouvelle-Aquitaine",
      cover: "la-coorniche",
      intro: [
        "La Nouvelle-Aquitaine a le goût des belles choses : la dune du Pilat au coucher du soleil, les grands crus de Bordeaux, les rivières du Périgord et les forêts profondes de la Charente limousine.",
        "Mes adresses y cultivent l'art de vivre : design face à l'océan, vinothérapie au milieu des vignes, château de conte de fées et moulin du XVIIe siècle au fil de l'eau.",
      ],
      tips: [
        "Pour la dune du Pilat, montez au coucher du soleil ou tôt le matin : la lumière est magique et la foule absente.",
        "Autour de Bordeaux, réservez vos visites de châteaux viticoles à l'avance, surtout le week-end.",
        "Dans le Périgord, Brantôme et ses bords de Dronne se découvrent très bien en canoë.",
      ],
    },
    {
      slug: "hotels-insolites-bourgogne-franche-comte",
      cat: "region",
      kicker: "Bourgogne-Franche-Comté",
      short: "Insolite en Bourgogne-Franche-Comté",
      title: (n) => `Bourgogne-Franche-Comté : ${n} nuits insolites au fil de l'eau`,
      description: "Cabanes flottantes au milieu des étangs, bateau-cabane sur le canal de Bourgogne, château rempli d'art contemporain près de Chablis : les nuits insolites de Bourgogne-Franche-Comté.",
      match: (h) => h.region === "Bourgogne-Franche-Comté",
      cover: "toue-cabanee-canal-de-bourgogne",
      intro: [
        "Canaux paisibles, étangs brumeux et vignobles de renom : la Bourgogne-Franche-Comté se vit au rythme lent de l'eau. On y dort dans une cabane flottante, sur un bateau amarré devant une maison d'éclusier ou dans un château du XVIIe siècle transformé en galerie d'art.",
        "Des adresses parfaites pour ralentir, pédaler le long des chemins de halage et goûter aux grands vins de la région.",
      ],
      tips: [
        "Le canal de Bourgogne se longe à vélo sur des dizaines de kilomètres : c'est la meilleure façon de le découvrir.",
        "Autour de Chablis, réservez une dégustation chez un vigneron : c'est souvent gratuit sur rendez-vous.",
        "Au printemps et à l'automne, les brumes matinales sur l'eau sont magnifiques : levez-vous tôt.",
      ],
    },
    {
      slug: "week-end-insolite-en-automne",
      cat: "envie",
      kicker: "Automne",
      short: "Week-end insolite en automne",
      title: (n) => `Week-end insolite en automne : ${n} adresses pour savourer la saison`,
      description: "Forêts qui rougissent, vendanges, bains nordiques fumants et cheminées : mes adresses insolites préférées pour un week-end d'automne en France, de la Toussaint à novembre.",
      ids: ["cabane-du-perche", "loire-valley-lodges", "landifornia-lodge", "cabanes-du-goutty", "lieu-dieu", "sources-de-caudalie", "villa-la-coste", "domaine-des-etangs", "pella-roca", "nids-des-vosges", "domaine-du-chatelet", "dihan"],
      cover: "cabane-du-perche",
      intro: [
        "L'automne est la plus belle saison des cabanes : les forêts se colorent, la lumière devient dorée, et l'on retrouve avec bonheur le crépitement d'un poêle à bois ou la chaleur d'un bain nordique quand l'air fraîchit. C'est aussi le temps des vendanges dans les vignobles et des brumes du matin sur les étangs.",
        "J'ai réuni des adresses qui se vivent particulièrement bien d'octobre à novembre : cabanes en forêt, bains chauds en plein air, domaines viticoles et grands parcs aux arbres centenaires. Idéal pour un pont de la Toussaint ou un week-end de novembre, loin de la foule de l'été.",
      ],
      faq: [
        ["Où partir en week-end insolite en automne ?", "En forêt, pour les couleurs, ou dans les vignobles, pour l'ambiance des vendanges. Une cabane avec bain nordique ou spa privatif est idéale : on profite de la nature même quand il fait frais."],
        ["Les cabanes sont-elles chauffées en automne ?", "La plupart des adresses de ce guide sont chauffées (poêle, chauffage d'appoint ou au sol). Vérifiez sur chaque fiche : certaines cabanes très simples ont seulement un chauffage d'appoint."],
        ["Les prix sont-ils plus bas en automne ?", "Souvent, oui : hors vacances de la Toussaint, l'automne est une saison plus calme, et les disponibilités sont plus nombreuses le week-end qu'en été."],
      ],
      tips: [
        "Pour la Toussaint, réservez dès septembre : c'est la seule période d'automne vraiment chargée.",
        "Emportez des vêtements chauds et une lampe frontale : les soirées tombent tôt en forêt.",
        "Vérifiez les dates d'ouverture : quelques lieux ferment leurs hébergements les plus simples en fin de saison.",
      ],
    },
    {
      slug: "nuit-insolite-en-hiver",
      cat: "envie",
      kicker: "Hiver",
      short: "Nuit insolite en hiver",
      title: (n) => `Nuit insolite en hiver : ${n} adresses cocon, entre neige et bain chaud`,
      description: "Igloo sur les pistes, chalet d'altitude, cabane avec bain nordique sous la neige, marchés de Noël d'Alsace ou Fête des Lumières à Lyon : mes nuits insolites préférées pour l'hiver.",
      ids: ["village-igloo-val-thorens", "refuge-de-solaise", "fermes-de-marie", "domaine-du-chatelet", "cabane-du-perche", "landifornia-lodge", "villa-rene-lalique", "cour-des-loges"],
      cover: "village-igloo-val-thorens",
      intro: [
        "L'hiver est la saison des nuits cocon : un igloo sculpté dans la neige, un refuge au sommet des pistes, un bain chaud fumant sous les flocons, ou une grande maison au coin du feu. Il suffit d'une nuit pour que la saison froide devienne la plus belle de l'année.",
        "Ma sélection mêle la haute montagne, pour les amoureux de neige, et des adresses de plaine ouvertes toute l'année, parfaites pour les fêtes : les marchés de Noël d'Alsace autour de la Villa René Lalique, ou la Fête des Lumières de Lyon depuis les cours Renaissance du Vieux Lyon.",
      ],
      faq: [
        ["Où dormir dans un igloo en France ?", "Le Village Igloo de Val Thorens propose des nuits dans des igloos sculptés, au cœur du domaine skiable, de fin décembre à mi-avril environ. Les places sont rares : réservez tôt."],
        ["Quelle nuit insolite offrir à Noël ?", "Une cabane avec bain nordique ou spa privatif fait toujours plaisir, en toute saison. Pour un cadeau sans date, pensez au bon cadeau de l'établissement ou à un coffret séjour."],
        ["Peut-on faire un bain nordique quand il neige ?", "Oui, et c'est même le meilleur moment : l'eau est chauffée autour de 38 °C, et le contraste avec l'air froid est un vrai bonheur. Prévoyez un peignoir et des chaussons pour le retour."],
      ],
      tips: [
        "En montagne, vérifiez l'accès : certains lieux se rejoignent en remontée mécanique, en raquettes ou en dameuse, avec des horaires fixes.",
        "Pour Noël et le Nouvel An, réservez dès l'automne : ces nuits partent en premier.",
        "Emportez de bonnes chaussures : même en plaine, les chemins de forêt sont boueux en hiver.",
      ],
      gift: true,
    },
    {
      slug: "nouvel-an-insolite",
      cat: "envie",
      kicker: "Nouvel An",
      short: "Nouvel An insolite",
      title: (n) => `Nouvel An insolite : ${n} adresses pour changer d'année autrement`,
      description: "Igloo sur les pistes, refuge d'altitude, cabane avec bain nordique sous les étoiles, palais au cœur de Paris ou de Lyon : mes idées de nuits insolites pour fêter le Nouvel An en France.",
      ids: ["village-igloo-val-thorens", "refuge-de-solaise", "refuge-de-la-traye", "fermes-de-marie", "cabane-du-perche", "landifornia-lodge", "nids-des-vosges", "chateau-de-la-resle", "villa-rene-lalique", "cour-des-loges", "maison-souquet", "molitor"],
      cover: "refuge-de-la-traye",
      intro: [
        "Pour passer d'une année à l'autre, il y a la grande soirée en ville… et il y a le réveillon à deux ou entre amis dans un lieu qu'on n'oubliera pas : un refuge au-dessus des nuages, une cabane chauffée où l'on trinque dans un bain nordique, ou une adresse d'exception au cœur de Paris ou de Lyon.",
        "J'ai réuni des lieux qui se prêtent bien aux nuits d'hiver : en montagne pour les amoureux de neige, à la campagne pour le calme et le feu de bois, en ville pour ceux qui veulent finir la soirée à pied. Les dîners et soirées du 31 décembre changent chaque année : renseignez-vous directement auprès de l'établissement.",
      ],
      faq: [
        ["Où passer un Nouvel An insolite en France ?", "En montagne, dans un refuge d'altitude ou un igloo, pour un réveillon vraiment dépaysant ; à la campagne, dans une cabane avec bain nordique ou spa privatif, pour une soirée à deux au calme ; ou en ville, dans un hôtel historique, pour profiter de la fête sans prendre la voiture."],
        ["Quand réserver pour le 31 décembre ?", "Le plus tôt possible, idéalement dès l'automne : ces lieux comptent souvent très peu de chambres, et la nuit du 31 part en premier. Certains établissements demandent un séjour de deux nuits minimum pendant les fêtes."],
        ["Les établissements organisent-ils un dîner de réveillon ?", "Beaucoup d'hôtels et de refuges proposent un menu spécial le 31 décembre, souvent à réserver avec la chambre. Pour les cabanes, pensez aux paniers-repas ou au dîner livré quand ils existent. Le programme change chaque année : demandez-le à l'établissement."],
      ],
      tips: [
        "Vérifiez la durée minimum de séjour : pendant les fêtes, deux ou trois nuits sont parfois demandées.",
        "En montagne, regardez comment on rejoint le lieu le soir : certains refuges ne sont accessibles qu'en remontée mécanique ou en dameuse, à heures fixes.",
        "Le 1er janvier, beaucoup de restaurants et de commerces sont fermés : prévoyez le déjeuner.",
      ],
      gift: true,
    },
    {
      slug: "saint-valentin-nuit-insolite",
      cat: "envie",
      kicker: "Saint-Valentin",
      short: "Saint-Valentin insolite",
      title: (n) => `Saint-Valentin insolite : ${n} nuits romantiques pour le 14 février`,
      description: "Cabane avec jacuzzi privatif, bain nordique sous les étoiles, chalet-spa, hôtel secret à Paris : mes nuits insolites les plus romantiques pour fêter la Saint-Valentin en France.",
      ids: ["alpinest", "pella-roca", "loire-valley-lodges", "cabanes-du-moulin", "ecrin-d-auvergne", "landifornia-lodge", "cabane-du-perche", "nids-des-vosges", "hotel-particulier-montmartre", "maison-souquet", "cour-des-loges", "villa-rene-lalique"],
      cover: "alpinest",
      intro: [
        "En février, la nuit tombe tôt et l'air est vif : c'est le moment idéal pour une soirée cocon à deux. Un jacuzzi qui fume sous les étoiles, un poêle à bois qui crépite, un dîner livré à la porte de la cabane, ou un petit hôtel secret au cœur de Paris : il suffit d'une nuit pour faire de la Saint-Valentin un vrai souvenir.",
        "Toutes les adresses de ce guide sont choisies pour leur intimité, et la plupart offrent un spa, un bain nordique ou un jacuzzi privatif, précieux en plein hiver. Comme elles comptent très peu de chambres, le week-end du 14 février part vite.",
      ],
      faq: [
        ["Quelle nuit insolite réserver pour la Saint-Valentin ?", "En hiver, privilégiez un lieu chauffé avec un bain chaud privatif : cabane avec jacuzzi, bain nordique ou chalet-spa. Pour une escapade sans voiture, un hôtel de charme à Paris ou à Lyon est aussi une belle idée."],
        ["Quand réserver pour le 14 février ?", "Idéalement un à deux mois avant, dès début janvier au plus tard. Si le 14 tombe en semaine, le week-end le plus proche est le plus demandé : pensez aussi au week-end suivant, plus calme."],
        ["Combien coûte une nuit romantique insolite ?", "Comptez de 150 à 450 € la nuit pour deux selon le lieu, souvent avec le petit-déjeuner. Chaque fiche indique une fourchette de prix, et le tarif exact est donné sur le site officiel de l'établissement."],
      ],
      tips: [
        "Demandez à l'établissement les attentions possibles (bouteille, fleurs, dîner livré, massage en duo) : elles se réservent souvent à l'avance.",
        "Vérifiez que le lieu est bien ouvert en février : quelques hébergements très simples ferment l'hiver.",
        "Pour offrir la nuit sans date fixe, beaucoup d'adresses proposent des bons cadeaux.",
      ],
      gift: true,
    },
    {
      slug: "hotels-insolites-auvergne-rhone-alpes",
      cat: "region",
      kicker: "Auvergne-Rhône-Alpes",
      short: "Insolite en Auvergne-Rhône-Alpes",
      title: (n) => `Auvergne-Rhône-Alpes : ${n} nuits insolites, des volcans aux sommets des Alpes`,
      description: "Igloos et refuges d'altitude dans les Alpes, bulles en Savoie, cabanes sur pilotis au milieu d'un étang en Auvergne, palais historiques à Lyon : les hébergements insolites d'Auvergne-Rhône-Alpes.",
      match: (h) => h.region === "Auvergne-Rhône-Alpes",
      sort: (a, b) => (a.env === "montagne") - (b.env === "montagne") || a.budget - b.budget,
      cover: "refuge-de-la-traye",
      intro: [
        "Aucune région n'offre autant de contrastes : on peut s'endormir dans un igloo à Val Thorens, face à la Mer de Glace dans un refuge historique, dans une bulle au milieu des prairies savoyardes, ou dans une cabane sur pilotis au milieu d'un étang d'Auvergne.",
        "Lyon ajoute ses adresses chargées d'histoire, entre le Grand Hôtel-Dieu sous le dôme de Soufflot et les demeures Renaissance du Vieux Lyon. De quoi composer un week-end différent à chaque saison.",
      ],
      tips: [
        "En montagne, beaucoup de refuges ne sont ouverts qu'en saison (hiver et été) : vérifiez les dates sur chaque fiche.",
        "En Auvergne, les lacs et volcans se découvrent très bien à pied : prévoyez une journée de randonnée.",
        "À Lyon, réservez longtemps à l'avance pour la Fête des Lumières, début décembre.",
      ],
    },
    {
      slug: "hotels-insolites-grand-est",
      cat: "region",
      kicker: "Grand Est",
      short: "Insolite en Alsace et dans les Vosges",
      title: (n) => `Alsace et Vosges : ${n} nuits insolites dans le Grand Est`,
      description: "Cabanes perchées dans les forêts des Vosges, cabane avec spa privatif près de Gérardmer, suites de la villa de René Lalique : les nuits insolites du Grand Est.",
      match: (h) => h.region === "Grand Est",
      cover: "cabanes-du-goutty",
      intro: [
        "Les forêts des Vosges et d'Alsace sont faites pour les cabanes : on y dort au-dessus d'un ruisseau, face à un étang ou dans les arbres, à moins d'une heure de Strasbourg ou de Colmar.",
        "Et pour une grande occasion, la villa que René Lalique fit construire en 1920 à Wingen-sur-Moder est devenue un hôtel de six suites, avec une table doublement étoilée.",
      ],
      tips: [
        "En décembre, combinez votre nuit avec les marchés de Noël d'Alsace : réservez très tôt.",
        "Les cabanes des Vosges sont souvent simples (toilettes sèches, chauffage d'appoint) : lisez bien le descriptif avant de réserver.",
        "La route des Crêtes, entre les sommets des Vosges, est fermée en hiver : vérifiez avant de partir.",
      ],
    },
    {
      slug: "hotels-insolites-normandie",
      cat: "region",
      kicker: "Normandie",
      short: "Insolite en Normandie",
      title: (n) => `Normandie : ${n} nuits insolites, de la forêt au Mont-Saint-Michel`,
      description: "Cabane dans les arbres avec bain nordique dans le Perche, bulles et lodges en forêt, maison du XVe siècle dans les remparts du Mont-Saint-Michel : les nuits insolites de Normandie.",
      match: (h) => h.region === "Normandie",
      cover: "cabane-du-perche",
      intro: [
        "À deux heures de Paris, la Normandie cache des nuits insolites loin des foules : cabanes perchées dans les collines du Perche, bulles et lodges sous les hêtres d'une forêt domaniale, ou nuit dans les remparts du Mont-Saint-Michel.",
        "Une région idéale pour un week-end nature, en toute saison, entre bocage, forêts et côtes.",
      ],
      tips: [
        "Le Perche est à environ deux heures de Paris : parfait pour un départ le samedi matin.",
        "Autour du Mont-Saint-Michel, consultez les horaires des marées : la baie change complètement d'un moment à l'autre.",
        "Prévoyez un vêtement de pluie : le climat normand est changeant, même en été.",
      ],
    },
    {
      slug: "hotels-insolites-hauts-de-france",
      cat: "region",
      kicker: "Hauts-de-France",
      short: "Insolite dans le Nord",
      title: (n) => `Hauts-de-France : ${n} nuits insolites près de Lille, d'Arras et de la baie de Somme`,
      description: "Cabanes perchées dans la forêt de Phalempin, bulles avec jacuzzi privatif près d'Arras, cabane flottante avec bain nordique près de la baie de Somme : les nuits insolites des Hauts-de-France.",
      match: (h) => h.region === "Hauts-de-France",
      cover: "cabanes-de-blanche",
      intro: [
        "Pas besoin d'aller loin pour dormir autrement quand on vit dans le Nord : la forêt de Phalempin est à vingt minutes de Lille, et la campagne de l'Artois ou les étangs aux portes de la baie de Somme offrent un dépaysement complet.",
        "On y dort perché dans les arbres, dans une bulle transparente sous les étoiles ou dans une cabane qui flotte sur un étang, avec bain nordique privatif.",
      ],
      tips: [
        "Les bulles se réservent surtout d'avril à septembre : pour l'hiver, préférez une cabane chauffée avec bain chaud.",
        "Autour de la baie de Somme, allez voir les phoques à marée basse, avec un guide.",
        "Pour un cadeau, plusieurs de ces lieux vendent des bons cadeaux valables un an.",
      ],
    },
  ];

  /* ------------------------------------------------------------
   *  GUIDES « PRÈS DE [VILLE] » (générés automatiquement)
   *  Les adresses à moins de 250 km, triées par distance (12 au plus).
   *  Un guide n'est publié que s'il est vraiment utile : au moins
   *  5 adresses, dont 3 à moins de 150 km hors de Paris intra-muros.
   * ------------------------------------------------------------ */
  const CITIES = [
    { name: "Lyon", slug: "lyon", lat: 45.764, lng: 4.8357, around: "Entre les Alpes, le Beaujolais, les Dombes et les volcans d'Auvergne, Lyon est un point de départ idéal pour une nuit qui sort de l'ordinaire, et la ville elle-même cache quelques adresses d'exception." },
    { name: "Marseille", slug: "marseille", lat: 43.2965, lng: 5.3698, around: "Des calanques au Luberon, des vignes du pays d'Aix aux criques rouges de l'Estérel, les environs de Marseille regorgent de lieux où dormir autrement, souvent à moins d'une heure de route." },
    { name: "Bordeaux", slug: "bordeaux", lat: 44.8378, lng: -0.5792, around: "Vignobles, dune du Pilat, Périgord et vallée de la Dordogne : autour de Bordeaux, les idées d'escapade ne manquent pas pour un week-end hors du commun." },
    { name: "Toulouse", slug: "toulouse", lat: 43.6047, lng: 1.4442, around: "Des Pyrénées au Quercy, de la cité de Carcassonne aux causses du Lot, Toulouse est entourée de paysages spectaculaires, parfaits pour une nuit insolite le temps d'un week-end." },
    { name: "Nantes", slug: "nantes", lat: 47.2184, lng: -1.5536, around: "Entre la côte bretonne, les bords de Loire et les caves troglodytes du Saumurois, Nantes se trouve au carrefour de quelques-unes des plus belles nuits insolites de l'Ouest." },
    { name: "Nice", slug: "nice", lat: 43.7102, lng: 7.262, around: "Entre la Méditerranée et les sommets des Alpes du Sud, Nice permet de passer en quelques heures d'une villa les pieds dans l'eau à un refuge d'altitude." },
    { name: "Rennes", slug: "rennes", lat: 48.1173, lng: -1.6778, around: "Forêt de Brocéliande, golfe du Morbihan, côtes sauvages et vallée de la Loire : depuis Rennes, les nuits insolites se trouvent souvent à une ou deux heures de route." },
    { name: "Montpellier", slug: "montpellier", lat: 43.6108, lng: 3.8767, around: "Entre Camargue, Provence, Cévennes et pays cathare, Montpellier est idéalement placée pour partir dormir dans un lieu qui change vraiment du quotidien." },
    { name: "Grenoble", slug: "grenoble", lat: 45.1885, lng: 5.7245, around: "Au pied des massifs de Belledonne, de la Chartreuse et du Vercors, Grenoble ouvre la porte des Alpes : refuges, chalets d'altitude et villages d'igloos ne sont jamais très loin." },
    { name: "Tours", slug: "tours", lat: 47.3941, lng: 0.6848, around: "Au cœur de la vallée de la Loire, Tours est entourée de châteaux, de caves troglodytes et de forêts : c'est l'une des villes de France les mieux placées pour une nuit insolite." },
    { name: "Clermont-Ferrand", slug: "clermont-ferrand", lat: 45.7772, lng: 3.087, around: "Volcans, lacs de cratère et grands espaces : autour de Clermont-Ferrand, la nature d'Auvergne se prête parfaitement aux cabanes et aux refuges hors du temps." },
    { name: "Dijon", slug: "dijon", lat: 47.322, lng: 5.0415, around: "Canal de Bourgogne, grands crus, étangs et forêts du Morvan : autour de Dijon, on dort au fil de l'eau, dans un château ou au milieu des arbres." },
    { name: "Lille", slug: "lille", lat: 50.6292, lng: 3.0573, around: "Forêts du Nord, bocages de l'Artois et baie de Somme : autour de Lille, il est plus facile qu'on ne le croit de s'offrir une nuit dans les arbres ou au bord de l'eau." },
    { name: "Strasbourg", slug: "strasbourg", lat: 48.5734, lng: 7.7521, around: "Des Vosges du Nord aux crêtes des Hautes-Vosges, les forêts d'Alsace et de Lorraine abritent des cabanes perchées et des maisons d'exception à peu de distance de Strasbourg." },
    { name: "Annecy", slug: "annecy", lat: 45.8992, lng: 6.1294, around: "Entre le lac d'Annecy, les Aravis, le Mont-Blanc et la Tarentaise, les nuits d'exception en altitude ne sont qu'à une ou deux heures de route." },
    { name: "Angers", slug: "angers", lat: 47.4784, lng: -0.5632, around: "Le Saumurois et ses kilomètres de galeries troglodytes, les châteaux de la Loire et les vignobles de l'Anjou font des environs d'Angers un terrain de jeu rêvé pour dormir autrement." },
    { name: "Orléans", slug: "orleans", lat: 47.903, lng: 1.9093, around: "Entre la Sologne, les châteaux de la Loire et Paris à une heure de train, Orléans est un excellent point de départ pour une nuit insolite, près de chez soi." },
    { name: "Limoges", slug: "limoges", lat: 45.8336, lng: 1.2611, around: "Charente limousine, Périgord vert, plateau de Millevaches et vallée de la Dordogne : autour de Limoges, la campagne cache des adresses d'exception." },
  ];
  const TYPE_WORDS = { cabane: "cabanes perchées", bulle: "bulles", troglodyte: "troglodytes", phare: "phare", igloo: "igloos", chalet: "refuges et chalets", eau: "nuits sur l'eau", chateau: "châteaux", historique: "lieux chargés d'histoire", design: "hôtels design", mer: "adresses les pieds dans l'eau", vignoble: "nuits dans les vignes", etoiles: "nuits sous les étoiles", moulin: "moulins", train: "wagons" };
  const euro = (n) => `${n} €`;
  const listFr = (a) => (a.length > 1 ? `${a.slice(0, -1).join(", ")} et ${a[a.length - 1]}` : a[0] || "");

  function cityGuide(c) {
    const de = /^[AEIOUYÉÈÂ]/i.test(c.name) ? `d'${c.name}` : `de ${c.name}`;
    const dist = (h) => km(c, h);
    const round = (h) => Math.max(5, Math.round(dist(h) / 5) * 5);
    const inCity = (h) => dist(h) < 12;
    const pick = () => {
      const all = (global.HOTELS || []).filter((h) => dist(h) <= 250).sort((a, b) => dist(a) - dist(b));
      const close = all.filter((h) => dist(h) <= 150 && h.city !== "Paris");
      return all.length >= 5 && close.length >= 3 ? all.slice(0, 12) : [];
    };
    const types = (list) => {
      const count = {};
      list.forEach((h) => { count[h.type] = (count[h.type] || 0) + 1; });
      return Object.entries(count).sort((a, b) => b[1] - a[1]).map(([t]) => TYPE_WORDS[t]).filter(Boolean);
    };
    const budgets = (list) => {
      const B = global.BUDGETS || {};
      const lo = Math.min(...list.map((h) => h.budget)), hi = Math.max(...list.map((h) => h.budget));
      return [B[lo], B[hi]];
    };
    return {
      slug: `hotel-insolite-pres-de-${c.slug}`,
      cat: "ville",
      city: c,
      kicker: `Autour ${de}`,
      short: `Nuits insolites près ${de}`,
      title: (n) => `Hôtels insolites près ${de} : ${n} nuits hors du commun`,
      get description() {
        const list = pick();
        const names = list.filter((h) => !inCity(h)).slice(0, 3).map((h) => h.name);
        return `Week-end insolite autour ${de} : ${listFr(names)}… ${list.length} lieux extraordinaires classés par distance, avec prix et conseils pour réserver.`;
      },
      get ids() { return pick().map((h) => h.id); },
      // Photos de couverture variées d'une ville à l'autre (parmi les 3 adresses les plus proches)
      get cover() { const l = pick().filter((h) => !inCity(h)).slice(0, 3); return (l[CITIES.indexOf(c) % Math.max(1, l.length)] || {}).id; },
      note: (h) => (inCity(h) ? `En plein ${c.name}` : `À ${round(h)} km ${de} à vol d'oiseau`),
      get intro() {
        const list = pick();
        const out = list.filter((h) => !inCity(h));
        const near = out.filter((h) => dist(h) <= 100);
        const t = types(list).slice(0, 4);
        const first = out[0];
        return [
          c.around,
          `J'ai retenu ${list.length} adresses à moins de ${Math.ceil(dist(list[list.length - 1]) / 50) * 50} km, classées de la plus proche à la plus lointaine : ${listFr(t)}.` +
            (first ? ` La plus proche hors de la ville, ${first.name}, se trouve à environ ${round(first)} km ${de} à vol d'oiseau` + (near.length > 1 ? `, et ${near.length} lieux sont à moins de 100 km : de quoi partir le samedi matin sans avoir l'impression de passer le week-end sur la route.` : ".") : ""),
        ];
      },
      get faq() {
        const list = pick();
        if (!list.length) return [];
        const out = list.filter((h) => !inCity(h));
        const first = out[0] || list[0];
        const [lo, hi] = budgets(list);
        const cheap = list.filter((h) => h.budget <= 2);
        const train = list.filter((h) => (h.tags || []).includes("train"));
        const spa = list.filter((h) => /spa|jacuzzi|bain nordique|sauna/i.test((h.amenities || []).join(" ")));
        const faq = [
          [`Quel est l'hébergement insolite le plus proche ${de} ?`, `Parmi ma sélection, ${first.name} (${first.city}) est le plus proche, à environ ${round(first)} km ${de} à vol d'oiseau. ${first.tagline}.`],
          [`Combien coûte une nuit insolite près ${de} ?`, lo && hi ? `Selon les adresses de ce guide, comptez ${lo === hi ? lo.range : `de ${lo.range.replace(" la nuit", "")} à ${hi.range}`} pour deux personnes, selon le lieu et la saison.` + (cheap.length ? ` Les plus abordables : ${listFr(cheap.slice(0, 3).map((h) => h.name))}.` : "") + " Le prix exact est donné sur le site officiel de chaque établissement." : "Le prix exact est donné sur le site officiel de chaque établissement."],
        ];
        if (spa.length) faq.push([`Où dormir avec spa ou jacuzzi près ${de} ?`, `${listFr(spa.slice(0, 4).map((h) => `${h.name} (${h.city})`))} proposent un espace bien-être. Vérifiez sur chaque fiche s'il est privatif ou partagé.`]);
        faq.push(train.length
          ? [`Peut-on y aller sans voiture depuis ${c.name} ?`, `Oui pour certaines adresses : ${listFr(train.slice(0, 4).map((h) => h.name))} ${train.length > 1 ? "sont accessibles" : "est accessible"} en train (parfois avec un court transfert en taxi ou à vélo). Pour les autres, la voiture reste le plus pratique.`]
          : [`Faut-il une voiture pour ces adresses autour ${de} ?`, "Dans la plupart des cas, oui : ces lieux sont souvent en pleine nature. Certains établissements peuvent organiser un transfert depuis la gare la plus proche : demandez-leur au moment de réserver."]);
        return faq;
      },
      get tips() {
        const list = pick();
        const near = list.filter((h) => !inCity(h) && dist(h) <= 100);
        return [
          near.length ? `Pour une seule nuit, visez les adresses à moins de 100 km (${listFr(near.slice(0, 3).map((h) => h.name))}) : vous profitez du lieu dès l'après-midi.` : "La plupart de ces adresses méritent au moins deux nuits : partez le vendredi soir ou posez un jour pour profiter du lieu sans courir.",
          "Les distances indiquées sont à vol d'oiseau : comptez davantage par la route, surtout en montagne ou en pleine campagne.",
          "Ces lieux comptent souvent très peu de chambres ou de cabanes : pour un week-end précis, réservez plusieurs semaines à l'avance.",
        ];
      },
    };
  }
  global.GUIDES.push(...CITIES.map(cityGuide));

  /* ------------------------------------------------------------
   *  GUIDES PAR ÉQUIPEMENT ET PAR TYPE DE LIEU
   *  Fondés sur les équipements vérifiés de chaque fiche
   *  (data/hotels-infos.json, recopiés dans h.infos.e par scripts/build.js).
   * ------------------------------------------------------------ */
  const hasEquip = (k) => (h) => ((h.infos && h.infos.e) || []).includes(k);
  const testedFirst = (a, b) => (b.review ? 1 : 0) - (a.review ? 1 : 0);
  global.GUIDES.push(
    {
      slug: "hotel-insolite-avec-piscine",
      cat: "envie",
      kicker: "Piscine",
      short: "Hôtels insolites avec piscine",
      title: (n) => `${n} hôtels insolites avec piscine en France`,
      description: "Piscine Art déco à Paris, bassin d'eau de mer taillé dans la roche de l'Esterel, piscine creusée dans le tuffeau, piscine face à la dune du Pilat : les hôtels insolites où l'on se baigne.",
      match: hasEquip("piscine"),
      sort: testedFirst,
      min: 4,
      cover: "les-roches-rouges",
      intro: [
        "Une piscine change un séjour : on y passe la fin d'après-midi, on y revient le matin avant le petit-déjeuner, et le lieu devient une vraie parenthèse. J'ai réuni ici les adresses de ma sélection qui en ont une, des plus spectaculaires (le bassin Art déco de Molitor, la piscine d'eau de mer des Roches Rouges, celle creusée dans la roche de la Demeure de la Vignole) aux plus discrètes.",
        "Selon les lieux, la piscine est intérieure ou extérieure, chauffée ou non, ouverte toute l'année ou seulement à la belle saison. Dans le doute, posez la question à l'établissement avant de réserver.",
      ],
      faq: [
        ["Quels hôtels insolites ont une piscine où se baigner en hiver ?", "Les piscines intérieures ou chauffées se profitent toute l'année : c'est le cas notamment de Molitor et du Parister à Paris, des Fermes de Marie à Megève et de la Cour des Loges à Lyon. Les piscines extérieures non chauffées sont en général fermées hors saison."],
        ["Y a-t-il des cabanes avec piscine ?", "Oui : Loire Valley Lodges a une piscine de 20 mètres au milieu de sa forêt, et Pella Roca une piscine chauffée face à la vallée du Quercy. Pour un bain rien qu'à deux, voyez aussi mon guide des nuits avec spa ou jacuzzi privatif."],
      ],
      tips: [
        "Demandez les horaires de la piscine en arrivant : dans les hôtels de ville, elle ferme souvent en début de soirée.",
        "En été, réservez tôt les adresses du bord de mer et de Provence : leur piscine fait une bonne part de leur succès.",
        "Emportez votre maillot même en hiver : piscine intérieure ou bain chaud, c'est souvent le meilleur moment du séjour.",
      ],
    },
    {
      slug: "hotel-insolite-avec-spa",
      cat: "envie",
      kicker: "Spa",
      short: "Hôtels insolites avec spa",
      title: (n) => `Hôtels insolites avec spa : ${n} adresses pour se ressourcer`,
      description: "Spa d'altitude face au Mont-Blanc, vinothérapie au milieu des grands crus, spa d'un château de conte de fées : les hôtels insolites avec spa pour un vrai week-end bien-être.",
      match: hasEquip("spa"),
      sort: testedFirst,
      min: 4,
      cover: "sources-de-caudalie",
      intro: [
        "Un week-end bien-être n'a pas besoin d'être banal. Ces adresses associent un lieu hors du commun et un vrai spa : on passe du sauna au hammam dans un hameau de fermes d'alpage à Megève, on se fait masser au milieu des grands crus de Bordeaux, ou l'on termine la journée au spa d'un château perdu au milieu des étangs de Charente.",
        "J'y ai aussi rangé les domaines de cabanes dont l'espace bien-être se partage entre les hôtes. Si vous rêvez d'un bain rien qu'à deux, mon guide des nuits avec spa ou jacuzzi privatif est fait pour vous.",
      ],
      faq: [
        ["Le spa est-il compris dans le prix de la chambre ?", "Cela dépend des lieux : l'accès à la piscine, au sauna ou au hammam est souvent inclus pour les clients de l'hôtel, tandis que les soins et les massages sont payants et se réservent à part. Vérifiez-le sur le site officiel au moment de réserver."],
        ["Peut-on aller au spa sans dormir à l'hôtel ?", "Certains spas d'hôtel accueillent des clients de passage, souvent en semaine et sur réservation, mais les clients de l'hôtel restent prioritaires. Renseignez-vous directement auprès de l'établissement."],
      ],
      tips: [
        "Réservez vos soins en même temps que votre chambre : les créneaux du samedi partent vite.",
        "Demandez si vous pouvez profiter du spa avant de prendre votre chambre ou après l'avoir rendue : c'est souvent possible.",
        "Pensez au maillot de bain, et parfois au bonnet si le spa a une piscine.",
      ],
    },
    {
      slug: "cabane-avec-jacuzzi-privatif",
      cat: "lieu",
      kicker: "Cabane & jacuzzi",
      short: "Cabanes avec jacuzzi privatif",
      title: (n) => `${n} cabanes et bulles avec jacuzzi ou bain nordique privatif`,
      description: "Cabane perchée avec jacuzzi sur la terrasse, bulle transparente et son bain chaud, cabane-spa au bord de la rivière : les cabanes avec spa privatif en France, pour deux.",
      match: (h) => (h.type === "cabane" || h.type === "bulle") && hasEquip("jacuzzi-privatif")(h),
      min: 4,
      cover: "cabanes-du-moulin",
      intro: [
        "C'est la recherche la plus fréquente pour une nuit insolite, et je comprends pourquoi : une cabane dans les arbres, une terrasse rien qu'à vous et un bain chaud qui vous attend, à l'heure que vous voulez, sous les étoiles ou sous la pluie.",
        "Selon les adresses, il s'agit d'un jacuzzi, d'un bain nordique chauffé au feu de bois ou d'un spa installé dans la cabane, réservé à votre seul hébergement. Sur certains domaines, seules quelques cabanes en ont un : vérifiez bien le nom de la cabane en réservant.",
      ],
      faq: [
        ["Où trouver une cabane avec jacuzzi près de Paris ?", "Les Cabanes du Moulin, à Orly-sur-Morin en Seine-et-Marne, sont les plus proches de Paris : trois cabanes-spa perchées au bord de la rivière. La Cabane du Perche, avec son bain nordique face aux collines, est une autre belle idée de week-end."],
        ["Quelle différence entre un jacuzzi et un bain nordique ?", "Le jacuzzi est un bain à bulles chauffé à l'électricité, prêt à toute heure. Le bain nordique est une grande cuve en bois, souvent chauffée au feu de bois, autour de 38 °C : plus rustique, il demande un peu de temps pour chauffer, mais c'est tout son charme."],
      ],
      tips: [
        "Un bain nordique met plusieurs heures à chauffer : prévenez de votre heure d'arrivée pour qu'il soit prêt.",
        "En hiver, gardez un bonnet : la tête au froid et le corps dans l'eau chaude, c'est tout le plaisir.",
        "Les week-ends d'hiver et la Saint-Valentin se réservent des mois à l'avance dans ces cabanes : n'attendez pas.",
      ],
    },
    {
      slug: "hotel-avec-table-etoilee",
      cat: "envie",
      kicker: "Gastronomie",
      short: "Dormir près d'une table étoilée",
      title: (n) => `Escapade gastronomique : ${n} hôtels d'exception avec table étoilée`,
      description: "Dîner étoilé, puis monter se coucher : un château en Charente, la maison du maître verrier Lalique, les grands crus de Bordeaux, la vallée de la Dordogne. Mes adresses avec table étoilée.",
      match: hasEquip("table-etoilee"),
      min: 3,
      cover: "villa-rene-lalique",
      intro: [
        "Le plus beau des dîners est celui après lequel on n'a pas à reprendre la voiture. Ces adresses abritent une table étoilée par le guide Michelin : on dîne longuement, on se laisse guider sur les vins, puis on monte simplement se coucher.",
        "Ce sont des lieux d'exception, et leurs prix le sont aussi : une escapade à réserver pour une grande occasion, un anniversaire ou une demande en mariage.",
      ],
      faq: [
        ["Faut-il dormir à l'hôtel pour dîner à sa table étoilée ?", "Non, ces restaurants sont en général ouverts à tous sur réservation. Mais dormir sur place change tout : pas de route de nuit après le dîner, et le petit-déjeuner du lendemain est souvent à la hauteur de la table."],
        ["Existe-t-il des formules dîner et nuit ?", "Plusieurs de ces établissements proposent des séjours gastronomiques (chambre, dîner et petit-déjeuner) sur leur site officiel. Réserver en direct vous permet aussi de demander la table et l'heure qui vous conviennent."],
      ],
      tips: [
        "Réservez la table en même temps que la chambre : les restaurants étoilés ont peu de couverts, et ferment souvent un ou deux soirs par semaine.",
        "Signalez allergies et régimes particuliers dès la réservation : la cuisine prépare ses produits à l'avance.",
        "Prévoyez une tenue un peu habillée : sans être obligatoire, elle fait partie du plaisir de la soirée.",
      ],
    },
    {
      slug: "hotel-insolite-avec-restaurant",
      cat: "envie",
      kicker: "Restaurant sur place",
      short: "Nuits insolites avec restaurant",
      title: (n) => `${n} nuits insolites avec restaurant sur place`,
      description: "Dîner dans une abbaye royale, dans les remparts du Mont-Saint-Michel ou au bord de la Mer de Glace, puis rentrer à pied : les nuits insolites où l'on dîne sur place.",
      match: hasEquip("restaurant"),
      sort: testedFirst,
      min: 4,
      cover: "fontevraud-l-ermitage",
      intro: [
        "Dans une cabane perdue en forêt ou un refuge d'altitude, la question du dîner se pose vite : faut-il reprendre la voiture, de nuit, sur une petite route ? Dans les adresses de ce guide, non. Le restaurant est sur place ou sur le domaine, et l'on rentre à pied après le dessert.",
        "Du bistrot de refuge à la grande table gastronomique, le style varie beaucoup d'une adresse à l'autre : regardez la carte sur le site officiel avant de partir, et réservez votre table en même temps que votre chambre.",
      ],
      faq: [
        ["Faut-il réserver le dîner à l'avance ?", "Oui, surtout le week-end : ces restaurants ont peu de tables et accueillent parfois aussi des clients de passage. Certains ferment un ou deux soirs par semaine : vérifiez les jours d'ouverture avant de choisir vos dates."],
        ["Existe-t-il des formules avec le dîner compris ?", "Plusieurs établissements proposent une demi-pension ou une formule « dîner et nuit » sur leur site officiel. C'est souvent plus simple que de réserver séparément, et sans commission quand vous réservez en direct."],
      ],
      tips: [
        "Arrivez avant la fin du service : dans les refuges et les domaines isolés, la cuisine ferme parfois tôt.",
        "Signalez allergies et régimes particuliers dès la réservation : loin de tout, la cuisine prévoit ses produits à l'avance.",
        "Demandez une table près de la fenêtre : la vue fait partie du repas.",
      ],
    },
    {
      slug: "nuit-insolite-avec-sauna",
      cat: "envie",
      kicker: "Sauna",
      short: "Nuits insolites avec sauna",
      title: (n) => `${n} nuits insolites avec sauna ou hammam`,
      description: "Sauna privatif dans une cabane des Vosges ou au bord d'un étang landais, hammam d'un hameau d'alpage à Megève, sauna d'un phare breton : les nuits insolites pour se détendre au chaud.",
      match: hasEquip("sauna"),
      min: 4,
      cover: "nids-des-vosges",
      intro: [
        "Le sauna est le meilleur ami des nuits insolites : après une journée de randonnée, de ski ou de route, quelques minutes de chaleur et l'on est prêt pour une vraie nuit de sommeil. Dans certaines cabanes, il est même privatif, installé dans la cabane ou au bord de l'eau.",
        "Ce guide réunit les adresses de ma sélection équipées d'un sauna ou d'un hammam, privatif ou partagé avec les autres hôtes : regardez la fiche et le site officiel pour savoir ce qu'il en est.",
      ],
      faq: [
        ["Quelle différence entre sauna, hammam et bain nordique ?", "Le sauna est une chaleur sèche, de 70 à 100 °C, dans une cabine en bois ; le hammam, une chaleur humide et plus douce, autour de 45 °C ; le bain nordique, une grande cuve d'eau chaude en plein air, autour de 38 °C."],
        ["Le sauna est-il privatif ?", "Cela dépend : à Pella Roca, aux Nids des Vosges ou à Landifornia Lodge, il est rattaché à certains hébergements ; dans les hôtels, il fait partie du spa et se partage avec les autres clients."],
      ],
      tips: [
        "Buvez beaucoup d'eau, avant comme après chaque séance.",
        "Alternez chaud et froid : une douche fraîche, un plongeon dans l'étang ou quelques pas dans la neige entre deux séances.",
        "Évitez le sauna juste après un repas copieux ou un verre de vin.",
      ],
    },
    {
      slug: "hotel-insolite-de-luxe",
      cat: "envie",
      kicker: "Exception",
      short: "Hôtels insolites de luxe",
      title: (n) => `Hôtels insolites de luxe : ${n} nuits d'exception en France`,
      description: "L'hôtel le plus haut de France, une villa sur sa presqu'île, le Grand Contrôle de Versailles, des bergeries corses face à la mer : les nuits insolites les plus luxueuses de ma sélection.",
      match: (h) => h.budget === 4,
      sort: testedFirst,
      min: 4,
      cover: "cap-estel",
      intro: [
        "Le luxe, pour moi, ce n'est ni le marbre ni la dorure : c'est un lieu unique, un service attentif et un souvenir qui reste. Ces adresses ont en commun des cadres que l'on ne trouve nulle part ailleurs : un observatoire à 2 877 mètres, un hameau de chalets que l'on rejoint à ski, le seul hôtel du domaine de Versailles.",
        "Ce sont les adresses les plus chères de ma sélection. Elles se réservent pour une grande occasion, et elles méritent souvent deux nuits plutôt qu'une.",
      ],
      get faq() {
        const B = (global.BUDGETS || {})[4];
        return [
          ["Combien coûte une nuit dans un hôtel insolite de luxe ?", `Pour les adresses de ce guide, comptez ${B ? B.range : "plus de 450 € la nuit"} pour deux personnes, selon la saison et la chambre. Le prix exact est donné sur le site officiel de chaque établissement.`],
          ["Comment rendre le séjour encore plus mémorable ?", "Réservez en direct et dites pourquoi vous venez (anniversaire, demande en mariage, voyage de noces) : les équipes de ces maisons aiment préparer une attention, et elles le font mieux quand elles le savent à l'avance."],
        ];
      },
      tips: [
        "Demandez quelle chambre a la plus belle vue : à budget égal, la différence peut être immense.",
        "Regardez les séjours en semaine ou hors saison : ces lieux y sont parfois nettement plus accessibles.",
        "Gardez du temps sur place : dans ces maisons, le séjour commence à l'arrivée, pas au dîner.",
      ],
    },
    {
      slug: "dormir-sur-l-eau",
      cat: "lieu",
      kicker: "Sur l'eau",
      short: "Dormir sur l'eau",
      title: (n) => `Dormir sur l'eau : ${n} cabanes flottantes, bateaux et hôtels sur l'eau`,
      description: "Hôtel flottant sur la Seine, bateau-cabane sur le canal de Bourgogne, cabanes sur pilotis rejointes en canoë, cabane flottante près de la baie de Somme : dormir sur l'eau en France.",
      match: (h) => h.type === "eau" || h.id === "cabanes-des-grands-lacs",
      min: 3,
      cover: "cabanes-lacustra",
      intro: [
        "S'endormir bercé par le clapotis, ouvrir les volets sur un étang couvert de brume : dormir sur l'eau est sans doute l'une des expériences les plus apaisantes qui soient. Ces adresses le permettent en pleine nature, mais aussi à Paris, sur la Seine.",
        "Cabane flottante avec bain nordique, toue amarrée devant une maison d'éclusier, cabanes sur pilotis que l'on rejoint en canoë : chacune a sa manière de vous mettre au fil de l'eau.",
      ],
      faq: [
        ["A-t-on le mal de mer en dormant sur l'eau ?", "Non : sur un étang, un canal ou la Seine, l'eau est calme et les hébergements sont amarrés ou posés sur pilotis. On sent tout au plus un léger mouvement, qui berce plus qu'il ne dérange."],
        ["Peut-on y aller avec des enfants ?", "Pour certaines adresses, oui, avec prudence : l'eau est partout autour. Les cabanes que l'on rejoint en canoë demandent de savoir nager ; demandez à l'établissement l'âge minimum et l'équipement fourni (gilets)."],
      ],
      tips: [
        "Prenez un pull même en été : au bord de l'eau, les soirées sont fraîches.",
        "Emportez un sac étanche si l'accès se fait en canoë.",
        "Les moustiques aiment l'eau autant que vous : un répulsif ne prend pas de place.",
      ],
    },
    {
      slug: "hotel-design-architecture",
      cat: "lieu",
      kicker: "Design & architecture",
      short: "Hôtels design et d'architecte",
      title: (n) => `Dormir chez un grand architecte : ${n} hôtels design en France`,
      description: "La Cité radieuse de Le Corbusier, la villa de René Lalique, la piscine Art déco Molitor, un pavillon revu par Philippe Starck, un vignoble signé Tadao Ando : dormir dans l'architecture.",
      match: (h) => h.type === "design" || h.id === "villa-la-coste",
      min: 3,
      cover: "hotel-le-corbusier",
      intro: [
        "Certains lieux se visitent ; ceux-ci se vivent, du soir au matin. Dormir dans la Cité radieuse de Le Corbusier, dans la maison que René Lalique s'est fait construire ou autour de la piscine Art déco de Molitor, c'est découvrir une architecture comme ses habitants la voient : à la lumière du matin, sans foule ni horaires de visite.",
        "Ce guide réunit les adresses de ma sélection où le bâtiment, ou le design, est la vraie raison du voyage.",
      ],
      faq: [
        ["Peut-on dormir dans la Cité radieuse de Le Corbusier ?", "Oui : l'Hôtel Le Corbusier occupe une partie de la Cité radieuse, à Marseille, inscrite au patrimoine mondial de l'UNESCO. C'est même l'une des adresses les plus abordables de ma sélection."],
        ["Ces lieux se visitent-ils sans y dormir ?", "Certains ouvrent leur restaurant, leur bar ou leurs jardins aux visiteurs, mais les chambres et les espaces privés restent réservés aux clients : c'est tout l'intérêt d'y passer la nuit."],
      ],
      tips: [
        "Demandez s'il existe une visite commentée du bâtiment : certains lieux en proposent à leurs clients.",
        "Réservez la chambre la plus emblématique quand c'est possible : c'est elle qui raconte l'histoire du lieu.",
        "Prenez le temps de regarder la lumière changer : ces architectures ont été pensées pour elle.",
      ],
    },
    {
      slug: "dormir-dans-un-monument-historique",
      cat: "lieu",
      kicker: "Lieux d'histoire",
      short: "Dormir dans un monument historique",
      title: (n) => `Dormir dans un monument historique : ${n} lieux chargés d'histoire`,
      description: "Une abbaye royale millénaire, une maison du XVe siècle dans les remparts du Mont-Saint-Michel, un hôpital de huit siècles à Lyon, la Cité de Carcassonne : dormir dans l'histoire.",
      match: (h) => h.type === "historique",
      min: 4,
      cover: "fontevraud-l-ermitage",
      intro: [
        "Il y a des lieux où l'on ne fait pas que dormir : on y passe une nuit dans l'histoire. Ici, l'abbaye royale où reposent Aliénor d'Aquitaine et Richard Cœur de Lion ; là, une maison à colombages du XVe siècle dans les remparts du Mont-Saint-Michel ; ailleurs, l'Hôtel-Dieu de Lyon, qui soigna les Lyonnais pendant huit siècles.",
        "Le grand privilège de ces adresses, c'est le soir : quand les visiteurs sont partis, le lieu est presque à vous. Se promener dans l'abbaye de Fontevraud ou dans les ruelles de la Cité de Carcassonne à la nuit tombée, aucune visite ne le remplace.",
      ],
      faq: [
        ["Peut-on profiter du monument quand on y dort ?", "C'est tout l'intérêt : à Fontevraud, on peut se promener dans l'abbaye à la nuit tombée ; au Mont-Saint-Michel ou dans la Cité de Carcassonne, on a les ruelles presque pour soi le soir et tôt le matin. Les conditions précises (horaires, billets) sont sur le site de chaque établissement."],
        ["Ces hôtels sont-ils accessibles aux personnes à mobilité réduite ?", "Pas toujours : escaliers anciens, ruelles pavées et bâtiments protégés limitent souvent les aménagements. Si c'est important pour vous, posez la question directement à l'établissement avant de réserver."],
      ],
      tips: [
        "Arrivez en fin d'après-midi, au moment où les visiteurs repartent.",
        "Levez-vous tôt au moins une fois : le monument au petit matin, sans personne, est inoubliable.",
        "Voyagez léger : ruelles pavées, escaliers à vis et accès piétons sont la règle dans ces lieux anciens.",
      ],
    },
  );

  /* ------------------------------------------------------------
   *  GUIDES « À MOINS DE … DE PARIS, LYON, BORDEAUX »
   *  Classés par temps de trajet réel :
   *  - train : train le plus rapide jusqu'à la gare (data/hotels-infos.json)
   *    + route entre la gare et l'hôtel (data/trajets-voiture.json) ;
   *  - voiture : route depuis le centre-ville (data/trajets-voiture.json,
   *    calculé par l'Action GitHub « Trajets »).
   *  Un guide n'est publié qu'avec au moins 4 adresses (min).
   * ------------------------------------------------------------ */
  const TRIP_CITY = {
    paris: { name: "Paris", lat: 48.8566, lng: 2.3522 },
    lyon: { name: "Lyon", lat: 45.764, lng: 4.8357 },
    bordeaux: { name: "Bordeaux", lat: 44.8378, lng: -0.5792 },
  };
  const tripOf = (h, c, mode) => {
    const I = h.infos;
    if (!I) return null;
    if (mode === "voiture") return I.v && typeof I.v[c] === "number" ? I.v[c] : null;
    const t = I.t && I.t[c];
    return t && typeof t[0] === "number" ? t[0] + (t[1] || 0) : null;
  };
  const inCityOf = (h, c) => { const t = h.infos && h.infos.t && h.infos.t[c]; return (t && t[0] === 0) || km(TRIP_CITY[c], h) < 12; };
  const sureOf = (h, c, mode) => mode === "voiture" || !!(h.infos && h.infos.t && h.infos.t[c] && h.infos.t[c][2]);
  const duree = (m) => (m < 60 ? `${m} min` : `${Math.floor(m / 60)} h${m % 60 ? ` ${String(m % 60).padStart(2, "0")}` : ""}`);
  const HOURS_WORD = { 120: "deux heures", 150: "deux heures et demie", 180: "trois heures" };

  function tripGuide(c, mode, max) {
    const F = TRIP_CITY[c];
    const de = `de ${F.name}`;
    const train = mode === "train";
    const lim = duree(max);
    const t = (h) => tripOf(h, c, mode);
    const ok = (h) => { const m = t(h); return m != null && m > 0 && m <= max && !inCityOf(h, c); };
    const pick = () => (global.HOTELS || []).filter(ok).sort((a, b) => t(a) - t(b));
    const label = (h) => `${sureOf(h, c, mode) ? "" : "environ "}${duree(t(h))}`;
    return {
      slug: `week-end-insolite-a-moins-de-${lim.replace(/ /g, "")}-de-${c}-en-${mode}`,
      cat: "trajet",
      kicker: train ? `En train depuis ${F.name}` : `En voiture depuis ${F.name}`,
      short: `À moins de ${lim} ${de} en ${mode}`,
      title: (n) => `Week-end insolite à moins de ${lim} ${de} en ${mode} : ${n} adresses`,
      get description() {
        const names = pick().slice(0, 3).map((h) => h.name);
        return `Week-end insolite à moins de ${lim} ${de} en ${mode} : ${listFr(names)}… Mes adresses classées par temps de trajet ${train ? "réel, de la gare à la porte" : "en voiture"}, avec prix et conseils.`;
      },
      match: ok,
      sort: (a, b) => t(a) - t(b),
      min: 4,
      note: (h) => {
        const s = label(h);
        return `${s[0].toUpperCase()}${s.slice(1)} ${train ? "en train" : "de route"} depuis ${F.name}`;
      },
      get cover() { const l = pick(); return (l.find((h) => (h.photos || 0) >= 4) || l[0] || {}).id; },
      get intro() {
        const list = pick();
        const first = list[0];
        const quick = list.filter((h) => t(h) <= 90);
        return [
          train
            ? `Partir ${de} le vendredi soir et dîner ${HOURS_WORD[max] || lim} plus tard dans une cabane ou un château, sans avoir touché un volant : c'est possible, et souvent plus reposant que la route. J'ai classé ici les adresses de ma sélection de la plus rapide à la plus lointaine en train.`
            : `Pas besoin de traverser la France pour changer d'air. Toutes ces adresses sont à moins de ${lim} de route ${de} : on part le samedi matin, on déjeune en chemin, et l'on a tout l'après-midi pour profiter du lieu.`,
          (train
            ? `Le temps indiqué va de la gare de départ à ${F.name} jusqu'à la porte de l'hôtel : le train le plus rapide, correspondances comprises, puis la route entre la gare d'arrivée et l'établissement (taxi, navette ou voiture de location).`
            : `Les temps de route sont calculés depuis le centre ${de}, par l'itinéraire le plus rapide et sans embouteillages : gardez une marge le vendredi soir et les veilles de vacances.`) +
            (first ? ` La plus rapide à rejoindre, ${first.name}, est à ${label(first)} ${de}` + (quick.length > 1 ? `, et ${quick.length} adresses sont à moins d'1 h 30.` : ".") : ""),
        ];
      },
      get faq() {
        const list = pick();
        if (!list.length) return [];
        const first = list[0];
        const noCar = list.filter((h) => (h.tags || []).includes("train"));
        const faq = [[
          train ? `Quel hôtel insolite rejoindre le plus vite en train depuis ${F.name} ?` : `Quel hôtel insolite est le plus proche ${de} en voiture ?`,
          `Dans ma sélection, ${first.name} (${first.city}) : ${label(first)} ${train ? `depuis ${F.name}, trajet entre la gare et l'hôtel compris` : `de route depuis le centre ${de}`}. ${first.tagline}.`,
        ]];
        if (train) {
          faq.push(["Comment sont calculés les temps de trajet ?", "J'additionne le train le plus rapide relevé sur les sites de réservation (SNCF Connect et comparateurs), correspondances comprises, et la route entre la gare d'arrivée et l'hôtel, calculée avec OpenStreetMap. Le trajet jusqu'à votre gare de départ n'est pas compté. Quand un horaire reste à confirmer, j'écris « environ »."]);
          faq.push(["Faut-il une voiture une fois arrivé ?", noCar.length
            ? `Pas pour ${listFr(noCar.slice(0, 4).map((h) => h.name))}, ${noCar.length > 1 ? "qui se rejoignent" : "qui se rejoint"} facilement sans voiture. Pour les autres adresses, réservez un taxi ou une voiture de location à la gare, ou demandez à l'établissement s'il organise un transfert.`
            : "Souvent, oui : réservez un taxi ou une voiture de location à la gare, ou demandez à l'établissement s'il organise un transfert depuis la gare."]);
        } else {
          faq.push(["Comment sont calculés les temps de route ?", `Ils sont calculés avec OpenStreetMap, du centre ${de} jusqu'à l'adresse de l'hôtel, par l'itinéraire le plus rapide et sans trafic. Ajoutez une marge les vendredis soir, les veilles de vacances et, l'hiver, sur les routes de montagne.`]);
        }
        return faq;
      },
      tips: train
        ? [
            "Réservez vos billets dès l'ouverture des ventes : les prix montent vite le vendredi soir et le dimanche après-midi.",
            "Demandez à l'hôtel s'il vient vous chercher à la gare, ou réservez un taxi à l'avance : dans les petites gares, il n'y en a pas toujours à l'arrivée.",
            "Voyagez léger : un sac souple se range partout, dans le train comme dans une cabane.",
          ]
        : [
            `Partez le samedi tôt ou le vendredi en fin de matinée pour éviter les bouchons de sortie ${de}.`,
            "Gardez de la marge pour les derniers kilomètres : chemins de terre et petites routes sont fréquents pour les lieux isolés.",
            "Voiture électrique ? Regardez la rubrique « Sur place » de chaque fiche : j'y indique le parking et la borne de recharge quand l'établissement les signale.",
          ],
    };
  }
  global.GUIDES.push(...[
    ["paris", "train", 120], ["paris", "train", 180], ["paris", "voiture", 120], ["paris", "voiture", 180],
    ["lyon", "train", 180], ["lyon", "voiture", 180],
    ["bordeaux", "train", 180], ["bordeaux", "voiture", 180],
  ].map(([c, mode, max]) => tripGuide(c, mode, max)));
})(typeof window !== "undefined" ? window : globalThis);
