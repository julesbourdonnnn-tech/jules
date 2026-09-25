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
    {
      slug: "week-end-insolite-en-automne",
      cat: "envie",
      kicker: "Automne",
      short: "Week-end insolite en automne",
      title: (n) => `Week-end insolite en automne : ${n} adresses pour savourer la saison`,
      description: "Forêts qui rougissent, vendanges, bains nordiques fumants et cheminées : nos adresses insolites préférées pour un week-end d'automne en France, de la Toussaint à novembre.",
      ids: ["cabane-du-perche", "loire-valley-lodges", "landifornia-lodge", "cabanes-du-goutty", "lieu-dieu", "sources-de-caudalie", "villa-la-coste", "domaine-des-etangs", "pella-roca", "nids-des-vosges", "domaine-du-chatelet", "dihan"],
      cover: "cabane-du-perche",
      intro: [
        "L'automne est la plus belle saison des cabanes : les forêts se colorent, la lumière devient dorée, et l'on retrouve avec bonheur le crépitement d'un poêle à bois ou la chaleur d'un bain nordique quand l'air fraîchit. C'est aussi le temps des vendanges dans les vignobles et des brumes du matin sur les étangs.",
        "Nous avons réuni des adresses qui se vivent particulièrement bien d'octobre à novembre : cabanes en forêt, bains chauds en plein air, domaines viticoles et grands parcs aux arbres centenaires. Idéal pour un pont de la Toussaint ou un week-end de novembre, loin de la foule de l'été.",
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
      description: "Igloo sur les pistes, chalet d'altitude, cabane avec bain nordique sous la neige, marchés de Noël d'Alsace ou Fête des Lumières à Lyon : nos nuits insolites préférées pour l'hiver.",
      ids: ["village-igloo-val-thorens", "refuge-de-solaise", "fermes-de-marie", "domaine-du-chatelet", "cabane-du-perche", "landifornia-lodge", "villa-rene-lalique", "cour-des-loges"],
      cover: "village-igloo-val-thorens",
      intro: [
        "L'hiver est la saison des nuits cocon : un igloo sculpté dans la neige, un refuge au sommet des pistes, un bain chaud fumant sous les flocons, ou une grande maison au coin du feu. Il suffit d'une nuit pour que la saison froide devienne la plus belle de l'année.",
        "Notre sélection mêle la haute montagne, pour les amoureux de neige, et des adresses de plaine ouvertes toute l'année, parfaites pour les fêtes : les marchés de Noël d'Alsace autour de la Villa René Lalique, ou la Fête des Lumières de Lyon depuis les cours Renaissance du Vieux Lyon.",
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
          `Nous avons retenu ${list.length} adresses à moins de ${Math.ceil(dist(list[list.length - 1]) / 50) * 50} km, classées de la plus proche à la plus lointaine : ${listFr(t)}.` +
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
          [`Quel est l'hébergement insolite le plus proche ${de} ?`, `Parmi notre sélection, ${first.name} (${first.city}) est le plus proche, à environ ${round(first)} km ${de} à vol d'oiseau. ${first.tagline}.`],
          [`Combien coûte une nuit insolite près ${de} ?`, lo && hi ? `Selon les adresses de ce guide, comptez ${lo === hi ? lo.range : `de ${lo.range.replace(" la nuit", "")} à ${hi.range}`} pour deux personnes, selon le lieu et la saison.` + (cheap.length ? ` Les plus abordables : ${listFr(cheap.slice(0, 3).map((h) => h.name))}.` : "") + " Le prix exact s'affiche dès que vous choisissez vos dates." : "Le prix exact s'affiche dès que vous choisissez vos dates."],
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
})(typeof window !== "undefined" ? window : globalThis);
