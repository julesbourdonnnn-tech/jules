export const meta = {
  name: 'roblox-market-to-gdd',
  description: 'Recherche marché Roblox 2025-2026 → rapport → 3 concepts → jury → GDD final',
  phases: [
    { title: 'Recherche', detail: '5 chercheurs web en parallèle' },
    { title: 'Rapport', detail: 'rapport de marché en français' },
    { title: 'Concepts', detail: '3 concepts originaux, angles différents' },
    { title: 'Jury', detail: '3 juges, lentilles différentes' },
    { title: 'GDD', detail: 'Game Design Document détaillé' },
  ],
}

const DOCS = '/home/user/jules/roblox-game/docs'

const RESEARCH_SCHEMA = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          evidence: { type: 'string' },
          source_url: { type: 'string' },
          as_of: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['claim', 'evidence', 'source_url', 'confidence'],
      },
    },
    key_takeaways_for_a_new_game: { type: 'array', items: { type: 'string' } },
  },
  required: ['topic', 'findings', 'key_takeaways_for_a_new_game'],
}

const COMMON_RESEARCH = `You are a senior Roblox market analyst. Today is 2026-10-30. Use WebSearch (send several searches in parallel; use mode "standard" first, "extended" for recent/niche facts) and WebFetch to gather CURRENT data (2025 through Oct 2026). Prefer primary/credible sources (Roblox Corporation investor relations & newsroom, Roblox DevForum/Creator Hub docs, RoMonitor Stats, Rolimons, reputable press like The Verge, Bloomberg, Polygon, Dexerto, GamesIndustry.biz, Naavik, Bloxbiz/GameFam reports). Every finding must cite a URL and say how recent it is. Mark uncertain numbers with confidence low. Aim for 12-25 high-value findings. Do not invent data.`

const RESEARCH = [
  { key: 'top-games', prompt: `${COMMON_RESEARCH}\n\nTOPIC: The top-performing Roblox experiences of 2025 and 2026 (up to Oct 2026). For 15-20 games give: peak concurrent users (record CCU), total visits, estimated revenue if reported, genre, core gameplay loop, launch date and growth speed, size of the team that made it, and WHY it succeeded (mechanics, social virality, update cadence, meme/trend factor). Include breakout hits from small/solo devs and record-breaking events (e.g. all-time CCU records). Also note which hits faded fast and why.` },
  { key: 'trends', prompt: `${COMMON_RESEARCH}\n\nTOPIC: Genre and mechanic trends on Roblox 2025-2026. Which genres/mechanics are rising vs declining (e.g. grow/farming/idle, collect-and-steal social loops, "brainrot" meme games, co-op survival, fishing, simulators, tycoons, obbies/tower climbers, horror co-op, anime fighters, tower defense, social hangouts, party/minigame games, competitive shooters). Lifecycle of trends (how fast clones appear, how long hits last), what kinds of mechanics produce viral social moments, what successful indie/small-team games did differently, and gaps/underserved niches with demand but little supply.` },
  { key: 'monetization-retention', prompt: `${COMMON_RESEARCH}\n\nTOPIC: Monetization, retention and discovery on Roblox in 2025-2026. Cover: how the Roblox discovery/recommendation algorithm ranks experiences (engagement, retention, qualified play-through, session time, monetization signals, ratings), changes to Home/Charts/Sort pages, ads & sponsored placements, the Creator Rewards / engagement-based payouts program, DevEx rate. What drives D1/D7/D30 retention (daily rewards, streaks, offline progress, limited-time stock rotations, global events, admin-abuse/live events, update cadence, quests, collection). Monetization norms: gamepass vs developer product mix, typical price points in Robux, best-converting offers (starter packs, 2x multipliers, VIP, skip-timers, server luck boosts), price optimization tools, regional pricing, subscriptions. Roblox policies on paid random items (loot boxes), and what monetization is considered fair vs predatory.` },
  { key: 'tech-polish', prompt: `${COMMON_RESEARCH}\n\nTOPIC: Technical excellence and polish for Roblox games in 2025-2026. Cover: what makes a Roblox game feel polished/"juicy" (UI tweening, feedback popups, particles, camera shake, sound, number animations, squash & stretch); mobile-first UX (share of mobile players, touch target sizes, safe areas, performance budgets for low-end phones, StreamingEnabled); networking/security best practices (server authority, RemoteEvent validation, rate limiting, never trusting the client, common exploits like remote spam and teleport/speed hacks); DataStore best practices (UpdateAsync, session locking, retries with backoff, BindToClose, budgets, data versioning/migration, ProfileStore); new Roblox engine/API features released 2025-2026 relevant to a new game (e.g. new type solver, UI styling, TextChatService, server authority/physics changes, avatar/animation changes, Experience Events, analytics, monetization APIs); Rojo-based professional workflow, testing (TestEZ/Jest-Lua/Lune), linting (Selene), formatting (StyLua). Note common causes of bugs in Roblox games and how top studios prevent them.` },
  { key: 'audience-compliance', prompt: `${COMMON_RESEARCH}\n\nTOPIC: Roblox audience and compliance 2025-2026. Cover: DAU and bookings figures, age demographics (under-13 vs 13+ vs 17+ share and trends), geographic split (incl. Europe/France), device split (mobile/PC/console/VR), language distribution and value of localization/auto-translation, content maturity labels and their impact on discoverability, age-check/age-estimation changes for chat and features in 2025-2026, policies affecting new experiences (paid random items, advertising standards, unrated experiences restrictions, creator verification requirements, publishing requirements like maturity questionnaire), and what different age groups prefer to play.` },
]

phase('Recherche')
const research = (await parallel(RESEARCH.map(r => () =>
  agent(r.prompt, { label: `recherche:${r.key}`, phase: 'Recherche', schema: RESEARCH_SCHEMA })
))).filter(Boolean)
log(`${research.length}/5 recherches terminées, ${research.reduce((n, r) => n + r.findings.length, 0)} constats`)

const researchDump = JSON.stringify(research, null, 1)
const takeaways = research.map(r => `### ${r.topic}\n` + r.key_takeaways_for_a_new_game.map(t => `- ${t}`).join('\n')).join('\n\n')

const HARD_CONSTRAINTS = `HARD CONSTRAINTS (all must hold):
1. ORIGINAL: may borrow popular GENRE mechanics, but must NOT recreate or clone any specific existing game (not even renamed). Original theme, world, names, twist and identity.
2. 100% buildable in code by an AI team using Rojo, without Roblox Studio manual work: NO uploaded custom meshes, images/decals, custom animations or required audio. Visuals come from Parts/WedgeParts/CornerWedge/Cylinder/Ball, Materials, colors, Neon, Lighting/Atmosphere/Sky/Clouds properties, ParticleEmitter, Beam, Trail, Highlight, PointLight/SpotLight, TweenService-driven motion, and UI fully built in code (Frame, TextLabel, TextButton, UIGradient, UIStroke, UICorner, UIScale). Default R15 avatars and default Roblox character animations only. Sounds optional (configurable IDs; the game must be fully playable silently).
3. Scope: the core game must be implementable in about 5,000-8,000 lines of Luau, robust and bug-free. Avoid bug-prone systems: vehicle physics, ragdoll/melee hit registration, complex NPC pathfinding, physics-replicated contraptions, building systems with free placement.
4. Multiplayer servers of 8-16 players with meaningful social interaction.
5. Mobile-first (most players on phones): big tap targets, minimal controls, also works on PC and gamepad.
6. First reward within 30 seconds; clear progression for 2-3+ weeks; daily return hooks.
7. Fair, policy-compliant monetization: gamepasses and developer products (placeholder IDs), NO paid random items, no pay-to-win that ruins fun for others.
8. All-ages friendly (content maturity Minimal or Mild).
9. Persistent progress (DataStore), server-authoritative economy.`

const CONCEPT_SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    tagline: { type: 'string' },
    pitch: { type: 'string' },
    genre_and_market_rationale: { type: 'string' },
    core_loop: { type: 'string' },
    first_five_minutes: { type: 'string' },
    progression: { type: 'string' },
    social_features: { type: 'string' },
    retention_hooks: { type: 'string' },
    monetization: { type: 'string' },
    juice_and_animation: { type: 'string' },
    world_and_art_direction_in_primitives: { type: 'string' },
    technical_feasibility: { type: 'string' },
    mvp_scope: { type: 'string' },
    risks: { type: 'string' },
    originality_statement: { type: 'string' },
  },
  required: ['name', 'tagline', 'pitch', 'genre_and_market_rationale', 'core_loop', 'first_five_minutes', 'progression', 'social_features', 'retention_hooks', 'monetization', 'juice_and_animation', 'world_and_art_direction_in_primitives', 'technical_feasibility', 'mvp_scope', 'risks', 'originality_statement'],
}

const ANGLES = [
  { key: 'trend-rider', angle: 'TREND RIDER: exploit the hottest 2025-2026 mechanics and social dynamics that drove record CCU (as found in the research) inside a fresh, original theme with a distinctive twist, maximizing virality and "watch other players" moments.' },
  { key: 'retention-architect', angle: 'RETENTION ARCHITECT: design around long-term retention and healthy monetization — collection, layered progression, offline/idle progress, daily/weekly loops, server-wide events, friend synergies — while keeping minute-to-minute play genuinely fun.' },
  { key: 'polish-first', angle: 'FUN-PER-LINE & POLISH FIRST: maximize fun per line of code and the "juice" a small team can deliver flawlessly; simple, readable mechanics with huge feedback, strong social moments, very low bug surface, very high polish on mobile.' },
]

phase('Rapport')
phase('Concepts')
const reportPromise = agent(`You are a senior Roblox market analyst writing for a French-speaking game creator who wants to launch a successful Roblox game. Using ONLY the research data below (do not invent numbers; keep source URLs), write a professional market analysis in FRENCH and save it with the Write tool to ${DOCS}/01-analyse-marche.md.

Structure: 1) Résumé exécutif (5-8 puces) 2) État du marché Roblox 2025-2026 (chiffres clés, audience, plateformes) 3) Les jeux qui cartonnent (tableau: jeu, genre, record CCU, boucle, pourquoi ça marche) 4) Tendances de genres et de mécaniques (montantes / en déclin / niches sous-exploitées) 5) Algorithme de découverte, rétention et monétisation (ce qui compte vraiment) 6) Qualité technique et "polish" : les standards attendus 7) Conformité et audience 8) Facteurs clés de succès pour un nouveau jeu en 2026 9) Recommandations stratégiques 10) Sources (liste des URL). Use tables where useful. Be precise, cite sources inline as [n] links. Length: thorough but readable (~250-450 lines).

Return a 10-line summary in French of the main conclusions.

RESEARCH DATA:
${researchDump}`, { label: 'rapport-marche', phase: 'Rapport' })

const conceptsPromise = parallel(ANGLES.map(a => () => agent(`You are an award-winning Roblox game designer and producer (multiple front-page hits). Design ONE original Roblox game concept with this angle:\n${a.angle}\n\n${HARD_CONSTRAINTS}\n\nGround every decision in the market research below. Be concrete: name the loop, the numbers (timings, rewards), the social moments, the exact juice per interaction, and how the world is drawn with primitives. Explain why it would rank well in Roblox discovery (engagement, retention, monetization). Be honest about risks.\n\nMARKET TAKEAWAYS:\n${takeaways}\n\nFULL RESEARCH:\n${researchDump}`, { label: `concept:${a.key}`, phase: 'Concepts', schema: CONCEPT_SCHEMA })))

const [reportSummary, conceptsRaw] = await Promise.all([reportPromise, conceptsPromise])
const concepts = conceptsRaw.filter(Boolean)
log(`Concepts: ${concepts.map(c => c.name).join(' | ')}`)

const JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    scores: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          concept_name: { type: 'string' },
          market_fit: { type: 'number' },
          fun: { type: 'number' },
          retention: { type: 'number' },
          monetization: { type: 'number' },
          feasibility_bug_free: { type: 'number' },
          originality_and_compliance: { type: 'number' },
          rationale: { type: 'string' },
        },
        required: ['concept_name', 'market_fit', 'fun', 'retention', 'monetization', 'feasibility_bug_free', 'originality_and_compliance', 'rationale'],
      },
    },
    best_ideas_to_graft: { type: 'array', items: { type: 'string' } },
    fatal_flaws: { type: 'array', items: { type: 'string' } },
  },
  required: ['scores', 'best_ideas_to_graft', 'fatal_flaws'],
}

const LENSES = [
  { key: 'publisher', lens: 'PUBLISHER / MARKET lens: which concept has the best chance to rank in Roblox discovery and grow CCU in 2026 given the research? Weigh market_fit and retention most.' },
  { key: 'lead-engineer', lens: 'LEAD ENGINEER lens: which concept can an AI team build in code only (no Studio assets) to a polished, bug-free, exploit-resistant state? Weigh feasibility_bug_free most; flag any hidden technical trap.' },
  { key: 'player', lens: 'PLAYER / FUN lens (think like 10-16 year old players on phones, and their friends): which one is the most fun in the first 5 minutes and still fun after a week? Weigh fun and social moments most. Also check originality: penalize anything that is effectively a clone of an existing game.' },
]

phase('Jury')
const conceptDump = JSON.stringify(concepts, null, 1)
const judgments = (await parallel(LENSES.map(l => () => agent(`You are a judge on a Roblox greenlight committee. ${l.lens}\n\nScore EACH concept 0-10 on every criterion (be discriminating, use the full scale). Then list the best ideas from ANY concept that should be grafted into the winner, and any fatal flaws.\n\n${HARD_CONSTRAINTS}\n\nMARKET TAKEAWAYS:\n${takeaways}\n\nCONCEPTS:\n${conceptDump}`, { label: `juge:${l.key}`, phase: 'Jury', schema: JUDGE_SCHEMA })))).filter(Boolean)

const WEIGHTS = { market_fit: 1.2, fun: 1.4, retention: 1.1, monetization: 0.7, feasibility_bug_free: 1.4, originality_and_compliance: 1.0 }
const totals = {}
for (const j of judgments) for (const s of j.scores) {
  let t = 0
  for (const k in WEIGHTS) t += (Number(s[k]) || 0) * WEIGHTS[k]
  const key = s.concept_name
  totals[key] = (totals[key] || 0) + t
}
const ranking = Object.entries(totals).sort((a, b) => b[1] - a[1])
log(`Classement: ${ranking.map(([n, t]) => `${n}=${t.toFixed(1)}`).join(', ')}`)
const winnerName = ranking[0][0]
const winner = concepts.find(c => c.name === winnerName) || concepts.find(c => winnerName.includes(c.name) || c.name.includes(winnerName)) || concepts[0]
const grafts = judgments.flatMap(j => j.best_ideas_to_graft)
const flaws = judgments.flatMap(j => j.fatal_flaws)

phase('GDD')
const gddSummary = await agent(`You are the lead game designer and technical director of a professional Roblox studio. The greenlight committee picked the concept below. Turn it into a complete, production-ready GAME DESIGN DOCUMENT in FRENCH and save it with the Write tool to ${DOCS}/02-game-design-document.md. Also save the jury results (ranking table, per-judge rationales, grafted ideas, rejected flaws) in French to ${DOCS}/03-decision-du-jury.md.

Integrate the best grafted ideas ONLY when they fit the scope and constraints; fix every fatal flaw the judges raised. Keep the concept original.

${HARD_CONSTRAINTS}

The GDD must be precise enough that engineers can implement it without guessing. Required sections:
1. Vision, pitch, piliers de design, public cible, positionnement marché (lié aux données du rapport)
2. Boucle de jeu principale (schéma texte), boucles secondaires, méta-progression
3. FTUE : les 5 premières minutes seconde par seconde (onboarding sans texte long)
4. Systèmes détaillés avec chiffres exacts: économie (monnaies, sources/puits), tableaux de coûts et courbes (formules), récompenses, durées, probabilités (si aléatoire gratuit), limites anti-abus
5. Contenu complet: liste des objets/zones/créatures/améliorations etc. avec statistiques (tableaux)
6. Social: interactions entre joueurs, moments viraux, classements
7. Rétention: récompenses quotidiennes (table), quêtes, événements serveur, mise à jour régulière
8. Monétisation: gamepasses et produits développeur (nom, prix en Robux, effet), règles d'équité
9. Juice & animation: pour CHAQUE interaction, les tweens (durée, easing), particules, effets caméra, popups, sons optionnels
10. UI/UX mobile-first: liste des écrans, disposition, tailles minimales, HUD, navigation manette/PC
11. Monde: plan de la carte construit en primitives (dimensions, positions approximatives en studs, palette de couleurs/matériaux, éclairage)
12. Architecture technique proposée: arbre Rojo (ReplicatedStorage/Shared, ServerScriptService, StarterPlayerScripts), liste des modules et responsabilités, liste des RemoteEvents/RemoteFunctions avec charges utiles et validation serveur, schéma de données sauvegardées (version, valeurs par défaut, migration), règles anti-exploit, budget performance
13. Localisation EN/FR (le jeu détecte la langue), accessibilité
14. Analytics (événements à suivre: funnel FTUE, économie, monétisation)
15. MVP (ce qui est livré maintenant) vs feuille de route post-lancement (mises à jour 2/4/8 semaines)
16. Risques et parades

Return a 15-line summary in French: name, pitch, core loop, key systems, monetization, why it should succeed.

WINNING CONCEPT:
${JSON.stringify(winner, null, 1)}

RANKING (weighted totals across 3 judges): ${JSON.stringify(ranking)}

JUDGE OUTPUTS:
${JSON.stringify(judgments, null, 1)}

ALL CONCEPTS (for grafting):
${conceptDump}

MARKET TAKEAWAYS:
${takeaways}

MARKET REPORT SUMMARY:
${reportSummary}`, { label: 'gdd', phase: 'GDD' })

return { ranking, winnerName: winner.name, reportSummary, gddSummary, grafts, flaws }
