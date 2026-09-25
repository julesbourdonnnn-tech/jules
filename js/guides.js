/*
 * ============================================================
 *  GUIDES THÉMATIQUES (pages « guides/<slug>.html »)
 * ============================================================
 *  Chaque guide sélectionne automatiquement les établissements de
 *  js/hotels.js qui correspondent à son thème (match) ou une liste
 *  choisie à la main (ids). Les titres s'adaptent au nombre d'adresses.
 *  cat : "envie" | "lieu" | "region" (rubrique de la page des guides).
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

  global.GUIDES = [
    {
      slug: "nuit-insolite-en-amoureux",
      cat: "envie",
      kicker: "En amoureux",
      short: "Nuits insolites en amoureux",
      title: (n) => `${n} nuits insolites pour un week-end en amoureux`,
      description: "Bulle sous les étoiles, phare, cabane avec jacuzzi, jardin secret à Montmartre : notre sélection d'hébergements insolites pour une escapade à deux en France.",
      ids: ["attrap-reves-allauch", "phare-de-kerbel", "loire-valley-lodges", "pella-roca", "hotel-particulier-montmartre", "les-roches-rouges", "la-coorniche", "alpinest", "cabanes-du-moulin", "les-hautes-roches", "bulles-de-savoie", "ecrin-d-auvergne"],
      cover: "attrap-reves-allauch",
      intro: [
        "Pour un anniversaire, une demande en mariage ou simplement deux jours rien qu'à deux, rien ne vaut un lieu qui sort de l'ordinaire. On a rassemblé ici nos adresses les plus romantiques : on s'y endort sous les étoiles, au sommet d'un phare ou dans les arbres, loin de tout.",
        "Elles cultivent toutes l'intimité, avec un décor qu'on n'oublie pas ; plusieurs offrent un spa ou un jacuzzi privatif.",
      ],
      faq: [
        ["Quelle est la nuit insolite la plus romantique de France ?", "Tout dépend de vos envies : une bulle transparente pour s'endormir sous les étoiles, le sommet d'un phare face à l'océan, ou une cabane perchée avec jacuzzi privatif. Les adresses de ce guide ont toutes été choisies pour leur intimité."],
        ["Combien coûte une nuit insolite en amoureux ?", "Comptez généralement de 150 à 450 € la nuit pour deux selon le lieu et la saison. Chaque fiche indique une fourchette de prix, et le tarif exact s'affiche dès que vous choisissez vos dates."],
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
      description: "Cabanes dans les arbres avec jacuzzi, cabanes d'artistes, cabanes flottantes : notre sélection des plus belles cabanes perchées où dormir en France.",
      match: (h) => h.type === "cabane",
      cover: "loire-valley-lodges",
      intro: [
        "Dormir dans les arbres, c'est retrouver ses rêves d'enfant avec le confort d'aujourd'hui. Les cabanes de notre sélection vont de l'adresse bohème au véritable hôtel de luxe perché, avec baies vitrées, jacuzzi privatif et dîner livré à la cabane.",
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
        ["Peut-on y aller en train ?", "Plusieurs adresses de la vallée de la Loire sont proches des gares de Tours ou de Saumur. Consultez aussi notre guide des nuits insolites accessibles sans voiture."],
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
      description: "Troglodytes, cabanes, bulle, hôtel Le Corbusier : les hébergements insolites de notre sélection à moins de 250 € la nuit (budget indicatif).",
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
        "Partir sans son chien, c'est souvent la moitié du plaisir en moins. Bonne nouvelle : plusieurs de nos adresses les plus remarquables l'accueillent volontiers, parfois avec gamelle, panier et friandise qui l'attendent dans la chambre.",
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
        "Nous avons choisi des lieux où l'intimité est garantie et où le cadre fait déjà la moitié du travail. À vous de trouver les mots.",
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
        "On a mêlé ici des adresses pour deux et des lieux à partager en famille ou entre amis, pour tous les budgets.",
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
      description: "Bulle, cabane-spa, phare, observatoire, château : nos idées pour offrir une nuit insolite en France, et comment faire un cadeau réussi (dates, bons cadeaux, coffrets).",
      ids: ["bulles-de-savoie", "pella-roca", "phare-de-kerbel", "pic-du-midi", "loire-valley-lodges", "ecrin-d-auvergne", "toue-cabanee-canal-de-bourgogne", "nids-des-vosges", "hotel-particulier-montmartre", "gare-de-guiscriff"],
      cover: "pella-roca",
      intro: [
        "Saint-Valentin, fête des mères, anniversaire, Noël : une nuit dans un lieu extraordinaire est l'un des cadeaux qui marquent le plus. On n'offre pas un objet, mais un souvenir à vivre.",
        "Voici nos idées les plus sûres, pour tous les budgets, et trois façons d'offrir : réserver des dates, demander un bon cadeau à l'établissement, ou choisir un coffret pour laisser le choix.",
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
        "Nos adresses y cultivent l'art de vivre : design face à l'océan, vinothérapie au milieu des vignes, château de conte de fées et moulin du XVIIe siècle au fil de l'eau.",
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
  ];
})(typeof window !== "undefined" ? window : globalThis);
