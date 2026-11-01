export const meta = {
  name: 'comet-conga-build',
  description: 'Construit Comet Conga : architecte → fondations → 6 lots implémentés+revus → intégration → QA adversariale → corrections',
  phases: [
    { title: 'Architecture', detail: 'contrat technique complet + stubs' },
    { title: 'Fondations', detail: 'logique pure + monde' },
    { title: 'Implémentation', detail: '6 lots, chacun implémenté puis revu' },
    { title: 'Intégration', detail: 'jeu complet, 12 joueurs simulés' },
    { title: 'QA', detail: '5 angles adversariaux, dont auditeur roblox-dev' },
    { title: 'Corrections', detail: 'correctifs groupés par lot + validation' },
    { title: 'Sauvegarde', detail: 'commit + push après chaque phase' },
  ],
}

const ROOT = '/home/user/jules/roblox-game'

const COMMON = `You are a senior engineer in a professional Roblox studio building the game "Comet Conga" with Luau + Rojo, entirely in code (no Roblox Studio work, no uploaded assets).
Repository root: ${ROOT} (git worktree, branch claude/roblox-game). Always cd there first.

SOURCE OF TRUTH
- Game design: docs/02-game-design-document.md (French; every number is there; §12 is the technical architecture).
- Technical contract: docs/04-architecture.md (module APIs, payloads, data ownership, package ownership). Read it fully before coding (if it exists).
- Project skills — read the relevant ones before coding: .claude/skills/roblox-luau-engineering/SKILL.md, roblox-security-datastore, roblox-ui-juice, roblox-qa-testing (test harness API), roblox-game-design.
- Existing tested foundation to REUSE, never rewrite: src/shared/{Net,Remotes}.luau, src/shared/Util/*, src/shared/Logic/Trail.luau, src/shared/Localization/*, src/server/Services/{DataService,MonetizationService}.luau, src/server/Util/{RateLimit,Analytics}.luau, src/server/World/{Build,Lighting}.luau, src/client/UI/{Root,Theme,Create,Juice,Toast}.luau, src/client/Controllers/{StateController,AudioController,WorldFXController}.luau, src/client/Util/Prices.luau, tests/harness/*.

TOOLS (in ~/.cargo/bin): stylua, selene, lune, rojo.
- Format your files: ~/.cargo/bin/stylua <files>
- Lint: ~/.cargo/bin/selene src  (0 errors required; fix warnings in your files)
- Tests: ~/.cargo/bin/lune run tests/run -- <filter>  (filter = substring of a spec path); whole suite: ~/.cargo/bin/lune run tests/run
- Full gate: ./scripts/check.sh

CODE RULES
- --!strict at the top of every src module; typed public APIs; comments in French, identifiers in English.
- task.wait/spawn/delay/defer only (wait/spawn/delay are banned and crash the harness).
- Server authority: clients send intents only; validate every remote payload (types, NaN/inf, ranges, ownership, sizes) and rate-limit with RateLimit.allow; never trust client values.
- Lifecycle: handle players already present; clean per-player state on PlayerRemoving; characters may be nil or respawn; client WaitForChild always with a timeout.
- Time: use the shared clock module defined in docs/04-architecture.md (never call os.time()/GetServerTimeNow() directly in services) so tests can time-travel.
- All player-facing text through Localization keys, with BOTH English and French in src/shared/Localization/Strings.luau.
- Data-driven: numbers/content come from src/shared/Config/*; never hardcode GDD numbers in services.
- Polish matters (the client asked for a fun, well-animated, bug-free game): follow GDD §9 juice specs with UI/Juice + TweenService; visuals are client-side only.
- Performance: decorative parts anchored and non-colliding; pool instances; one Heartbeat connection per system.

TEAMWORK RULES (other engineers edit this tree concurrently)
- Only create/modify the files your package owns. Exception: shared registries src/shared/Localization/Strings.luau, src/shared/Remotes.luau, src/shared/Config/Sounds.luau — to add entries, Read the file right before each Edit and make small targeted Edits (never rewrite these files). If another package's file must change, do not edit it: report it in integration_notes.
- No state-changing git commands (no commit/add/stash/checkout/reset).
- Never delete or weaken existing tests to make them pass.

DEFINITION OF DONE
- No TODO stubs left in your files; behavior matches the GDD and docs/04-architecture.md.
- Specs for your package in tests/specs/ covering happy paths, edge cases, malicious remote payloads and lifecycle (join/leave/respawn). If a dependency owned by another package is still a TODO stub, override its functions inside your spec (modules are plain tables) to isolate your code.
- selene src: 0 errors; your files formatted with stylua; run the whole suite at the end and report the result honestly.`

const ATTRIB = (args && args.attribution) || ''  // lignes d'attribution des commits, passées par args.attribution

async function checkpoint(label, message) {
  return agent(`You are a release helper. In ${ROOT} run exactly, in order:
1) ~/.cargo/bin/stylua src tests   (formatting only)
2) git add -A
3) git commit -m "${message}" -m "${ATTRIB}"   (if there is nothing to commit, skip to the end)
4) git push origin claude/roblox-game   (if it fails because of the network, retry up to 4 times waiting 2, 4, 8, 16 seconds)
Do not change any other file. Return one line: the new commit hash and whether the push succeeded.`, { label: `sauvegarde:${label}`, phase: 'Sauvegarde', effort: 'low' })
}

const ARCH_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    packages: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          key: { type: 'string' },
          owned_files: { type: 'array', items: { type: 'string' } },
          notes: { type: 'string' },
        },
        required: ['key', 'owned_files', 'notes'],
      },
    },
    check_passed: { type: 'boolean' },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'packages', 'check_passed', 'open_questions'],
}

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    package: { type: 'string' },
    summary: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    spec_files: { type: 'array', items: { type: 'string' } },
    own_tests_passing: { type: 'boolean' },
    full_suite_result: { type: 'string' },
    integration_notes: { type: 'array', items: { type: 'string' } },
    open_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['package', 'summary', 'files', 'spec_files', 'own_tests_passing', 'full_suite_result', 'integration_notes', 'open_issues'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          file: { type: 'string' },
          line: { type: 'number' },
          title: { type: 'string' },
          problem: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'file', 'title', 'problem', 'fix'],
      },
    },
  },
  required: ['findings'],
}

const PACKAGES = [
  { key: 'logic', gdd: '§4 (all systems, formulas), §4.7 snip rules order, §4.18 pacing simulation, §2.4 clock, §4.15 event timings, §11.1 map layout, §12.3-12.4, §12.9',
    scope: 'All pure modules in src/shared/Logic (Formulas, extend Trail with segment-segment XZ distance and the swept snip test, SeededPath, EventClock, Hash, WorldLayout, SnipRules) and their specs, plus tests/specs/EconomyPacing.spec.luau implementing the GDD §4.18 simulation gate (it must pass; if the median milestones fall outside tolerance, tune ONLY values in src/shared/Config/Balance.luau within the spirit of the GDD and document each change in docs/04-architecture.md under a "Réglages d\'économie" section).' },
  { key: 'world', gdd: '§11 (whole world), §5.1-5.2 (species and NebbyBuilder recipes), §9.3, §11.5 lighting & palette, §11.6, §12.8 budgets',
    scope: 'Render/NebbyBuilder (all recipes, LOD levels, rarity auras, forms and variants, pure constructor usable on client), server WorldService (builds Lumora with World/Build and Logic/WorldLayout: island disc, cliff skirt, invisible walls, 3 zone decors, Crater bowl and cracks, central Beacon, 12 Nests with gate/arch/perches/observatory/billboard, stepping-stone paths, lanterns within the light budget, floating islets, Clouds), src/first/Loading.client.luau (loading screen in code), client LightingController (12-minute dusk↔night cycle and weather presets with tweens).' },
  { key: 'conga', gdd: '§4.3-4.9, §4.15.2 comet pickup/steal hooks, §4.15.4 Gloomwisp snips, §4.16-4.17, §12.3-12.5, §12.7-12.8',
    scope: 'Server CongaService (10 Hz fixed-step tick orchestration, per-player Trail breadcrumbs, captures with spatial grid, snips via SnipRules + swept test with all protections, parades at own gate and Beacon ring, WalkSpeed ownership incl. slow/Dash/Second Wind/comet, line death/leave scatter, broadcasting PathStream/LineEvent/SnipEvent, WorldSnapshot/RequestWorld/RequestPath), SpawnService (wild Nebbies per zone with caps/intervals/lifetimes/SeededPath wander, loose Nebbies with dizzy/priority, personal onlyFor spawns, WildEvent batching at 4 Hz), Util/MoveCheck (anti-cheat per GDD §12.7), shared Logic/PathCodec (PathStream buffer encode/decode, round-trip tested).' },
  { key: 'economy', gdd: '§4.1-4.2, §4.8-4.14, §4.16 rookie/zen hooks for payouts, §8, §12.6',
    scope: 'Server EconomyService (lazy settle, offline earnings + return screen data, global multiplier M, upgrades purchase, Supernova with preview data and safe-harbor rule, personal/server boosts, Glow/Stardust sources), AtlasService (collection records with uids, auto-sort perches, stash cap and auto-release, locks, release for Stardust, Starforge fuse/fuseAll, Atlas bits + badges + milestones), NestService (nest assignment 1-12, owner color, perch display attributes, constellation, Supernova progress ring data), ProductService (handlers for every pass/product via MonetizationService.registerProduct/PassGranted, Starter Kit once, Glow Party queue).' },
  { key: 'events', gdd: '§4.15 (weather, Great Comet, Beacon Night, Frenzy, Golden Night, Gloomwisps, Starfall Saturday), §6 (crews, escort, pings, banners, cheers, leaderboards, Duo gift), §7 (return screen data, login calendar, onboarding quests, daily/weekly quests, codes), §4.16 rookie shield bookkeeping, §14 analytics',
    scope: 'Server EventService (EventClock-driven phases, comet lifecycle incl. carrier/steal/bank/burst, beacon bar with mercy, frenzy, golden night, gloomwisps positions + pops, starfall, server boosts, LiveOps via MessagingService with Data/Admins), QuestService (onboarding chain, daily quests deterministic draw + reroll, weekly, 7-day forgiving calendar, codes with Data/Codes, daily caps, rookie shield state), CrewService (auto crews of friends, invites accept/decline/leave, escort query API used by snips, pings, cheers, server banners queue, Duo gift), LeaderboardService (live server board + weekly OrderedDataStore boards with batching).' },
  { key: 'client-world', gdd: '§9.3-9.4 (world-space juice), §11.6, §12.4 (rendering from server breadcrumbs, gap recovery), §12.8 budgets',
    scope: 'Client WorldStateController (mirror of lines, paths via PathCodec, wild Nebbies, gloomwisps, comet, events, crews; WorldSnapshot on join; RequestPath/RequestWorld recovery), CongaRenderer (draw every line with NebbyBuilder + LOD + pooling + one BulkMoveTo per frame, local player line from local breadcrumbs, wild Nebbies wander via SeededPath, bobbing/blinking/facing, Gloomwisps and Comet rendering, perches display from Nest attributes), VFXController (catch hop+squash+burst, rarity pillars, snip stamp+scatter arcs+dizzy, parade march+fireworks, comet sky arc/impact/carrier ring+beam, supernova sequence, upgrade ring, dash trail/FOV — respecting Reduced Motion and Low Graphics).' },
  { key: 'client-hud', gdd: '§3 (FTUE second by second), §9.1-9.2, §10.1-10.2 HUD, §10.4 PC/gamepad, §6.3-6.5 pings/minimap/banners, §13.2 accessibility',
    scope: 'Client HUD (Glow counter with prediction and rolling, Stardust, conga meter + bonus, Dash button with radial cooldown, event pill with countdown, comet HUD, left icon rail opening panels via the panel API), Minimap (frames-based circle with players, comet, wisps), Banners (queued server banners), InputController (Dash/pings/menu shortcuts via ContextActionService, ping wheel, input type report), OnboardingController (footprints, arrows, progressive HUD reveal, quest hints), screen-space juice (PARADE stamp, floaters, coin fly to counter, toasts on Feedback).' },
  { key: 'client-panels', gdd: '§10.3 screens, §4.11-4.14 (upgrades, Supernova preview with 1 s hold, Starforge, Atlas), §7 (calendar, quests, return screen), §8 (shop with runtime prices), §6.1 crew UI, §13 settings/localization',
    scope: 'Client UI/Panels/* (Upgrades, Supernova, Collection with Atlas/Stash/Starforge/Guide odds tabs, Goals with calendar/daily/weekly/onboarding, Shop with passes/products via Prices and MarketplaceService prompts, Crew with invites, Settings incl. Zen/Reduced Motion/Low Graphics/music/sfx/language, ReturnScreen) and the panel navigation API used by the HUD (one panel open at a time, back/close, gamepad selection).' },
]

// ───────────────────────── Phase 1 : architecte
phase('Architecture')
const arch = await agent(`${COMMON}

ROLE: Lead architect. Produce the technical CONTRACT so that 8 engineers can implement Comet Conga in parallel without guessing and without editing each other's files.

Read fully first: docs/02-game-design-document.md, docs/03-decision-du-jury.md, every .claude/skills/*/SKILL.md, every file under src/ and tests/ (harness + specs).

DELIVERABLES
1. docs/04-architecture.md (French), containing:
   - Package ownership table: exact file paths per package key (keys listed below); every new file belongs to exactly one package; shared registries noted.
   - For EVERY module (server services, client controllers, UI modules, shared logic/render/config): purpose, public API as Luau signatures with types, signals it exposes, remotes it handles/fires, profile keys it owns (one owner per Schema key; others go through the owner's API), dependencies (only on modules earlier in the init order).
   - Server and client init orders (respect GDD §12.3) and the 10 Hz CongaService tick with the exact hooks it calls in other services.
   - Exact payload shapes of every remote (field names and types): LineEvent ops, WildEvent, SnipEvent, EventState, Banner kinds, Feedback keys, Celebrate kinds, WorldSnapshot, CrewState, etc., plus the PathStream binary format and its codec module src/shared/Logic/PathCodec.luau (owned by package conga).
   - Workspace layout: folders the server creates (e.g. workspace.Lumora, Nests), instance attributes and CollectionService tags that clients read (e.g. Nest owner/perch attributes), client-only folders.
   - Cross-package internal signals (e.g. a parade signal consumed by quests/leaderboards/analytics, snip/catch/comet signals) so packages integrate through documented signals.
   - A shared time source: src/shared/Util/Clock.luau (server time and UTC unix time, with a test override such as Clock.setOffset/Clock.freeze); every service must use it.
2. Contract code with REAL data (no placeholders):
   - src/shared/Config/Balance.luau, Nebbies.luau (all 36 species: id, name, rarity, archetype, accent colors, version mvp/v1.1; forms; variants; star multipliers), Zones.luau, Events.luau, Quests.luau (onboarding Q1-Q7, the 25 daily quests, weekly, calendar, Atlas milestones), Cosmetics.luau — exactly the GDD numbers and keys ([Balance.Snip.Radius] etc.).
   - src/shared/Config/Monetization.luau filled (6 passes, 6 products, ids 0, prices per GDD §8) and new keys in src/shared/Config/Sounds.luau (ids "").
   - src/shared/Types.luau with shared exported types (NebbyRecord, LineNode, WildNebby, EventState, payload types…).
   - src/shared/Util/Clock.luau (implemented and tested).
   - src/shared/Remotes.luau: every remote of GDD §12.5 (keep existing ones).
   - src/server/Data/Schema.luau: schema v1 per GDD §12.6 replacing the example coins field, with migrate() and PRIVATE_KEYS.
   - src/shared/Localization/Strings.luau: every key you can foresee for HUD, panels, banners, feedback, quests, settings, onboarding, species names stay English — in EN and FR.
   - default.project.json: add ReplicatedFirst → src/first and the project settings from GDD §12.2 (valid for rojo 7.7.1; verify with rojo build).
3. STUB files for every module owned by the implementation packages, with the exact public API you documented: Init()/Start() present and harmless (no-op), other public functions typed with body error("TODO(<package>): <Module>.<fn>"). Pure logic stubs likewise. Each stub begins with a French header comment listing its responsibilities and the GDD sections to implement.
4. Update src/server/Main.server.luau and src/client/Main.client.luau ORDER lists to include every service/controller in the documented order (stubs keep boot harmless).
5. Update existing specs that relied on the old example schema (coins) to the new schema WITHOUT weakening what they verify.
6. Gate: ./scripts/check.sh must pass.

PACKAGE KEYS AND SCOPES (assign concrete file paths to each):
${PACKAGES.map(p => `- ${p.key}: ${p.scope}`).join('\n')}

Return the structured result: packages[] must contain exactly these keys: ${PACKAGES.map(p => p.key).join(', ')}.`, { label: 'architecte', phase: 'Architecture', schema: ARCH_SCHEMA })

if (!arch) throw new Error('Architecte : aucun résultat')
log(`Architecture : ${arch.packages.length} lots, check=${arch.check_passed}`)
await checkpoint('architecture', 'Architecture : contrat technique, configuration complète, schéma v1 et interfaces')

const ownedBy = {}
for (const p of arch.packages) ownedBy[p.key] = p

function implPrompt(p) {
  const a = ownedBy[p.key] || { owned_files: [], notes: '' }
  return `${COMMON}

YOUR PACKAGE: ${p.key}
Scope: ${p.scope}
GDD sections to implement (read them closely): ${p.gdd}
Files you own (from the architect): ${a.owned_files.join(', ') || '(see docs/04-architecture.md)'}
Architect notes: ${a.notes}

Implement the package completely (replace every TODO stub you own with production code), write its specs, run them and the whole suite, and return the structured report.`
}

function reviewPrompt(p, impl) {
  const a = ownedBy[p.key] || { owned_files: [] }
  return `${COMMON}

ROLE: Senior reviewer for package ${p.key}, which another engineer has just implemented.
Scope: ${p.scope}
GDD sections: ${p.gdd}
Files of this package: ${(impl && impl.files && impl.files.length ? impl.files : a.owned_files).join(', ')}
Implementer report: ${JSON.stringify(impl || {}).slice(0, 4000)}

Review these files line by line against the GDD, docs/04-architecture.md and the skills. Hunt for: Roblox lifecycle bugs (races at join, respawn, leave during yields, nil character), unvalidated or unthrottled remotes, economy errors (negative/NaN/double rewards, wrong formulas vs GDD), missing GDD behaviors, missing or weak juice/animation where the GDD specifies it, performance traps, leaks, untested branches. FIX every real problem directly in this package's files (you now own them), add specs reproducing each bug before fixing it, re-run the specs and the whole suite. Return the structured report (summary = list of bugs found and fixed; open_issues = what you could not fix).`
}

// ───────────────────────── Phase 2 : fondations (logique + monde)
phase('Fondations')
const foundations = await parallel(['logic', 'world'].map(k => () => {
  const p = PACKAGES.find(x => x.key === k)
  return agent(implPrompt(p), { label: `impl:${k}`, phase: 'Fondations', schema: IMPL_SCHEMA })
}))
log(`Fondations : ${foundations.filter(Boolean).map(r => `${r.package} tests=${r.own_tests_passing}`).join(' | ')}`)
await checkpoint('fondations', 'Fondations : logique pure testée (formules, horloge, coupe, simulation économique) et monde de Lumora')

// ───────────────────────── Phase 3 : lots (implémentation puis revue)
phase('Implémentation')
const LOTS = ['conga', 'economy', 'events', 'client-world', 'client-hud', 'client-panels'].map(k => PACKAGES.find(x => x.key === k))
const lots = await pipeline(
  LOTS,
  p => agent(implPrompt(p), { label: `impl:${p.key}`, phase: 'Implémentation', schema: IMPL_SCHEMA }),
  (impl, p) => agent(reviewPrompt(p, impl), { label: `revue:${p.key}`, phase: 'Implémentation', schema: IMPL_SCHEMA }).then(r => ({ impl, review: r })),
)
const lotSummary = lots.filter(Boolean).map(x => ({
  package: x.impl && x.impl.package,
  impl: x.impl && x.impl.summary,
  review: x.review && x.review.summary,
  notes: [...((x.impl && x.impl.integration_notes) || []), ...((x.review && x.review.integration_notes) || [])],
  open: [...((x.impl && x.impl.open_issues) || []), ...((x.review && x.review.open_issues) || [])],
}))
log(`Lots terminés : ${lotSummary.length}/${LOTS.length}`)
await checkpoint('lots', 'Implémentation des lots : cœur conga, économie, événements et social, rendu client, HUD, panneaux')

// ───────────────────────── Phase 4 : intégration
phase('Intégration')
const integration = await agent(`${COMMON}

ROLE: Integration lead. All packages are implemented. Make the WHOLE game work end-to-end and leave the tree green.

RESUME NOTE: a previous integration attempt was interrupted by a container restart (the last commit 16b3ee5 is clean and green: 850 tests). Its partial, unverified work is still in the working tree: modified src/server/Services/EventService.luau and tests/specs/EventService.spec.luau, new tests/harness/Bots.luau and tests/specs/Boot.spec.luau. Run git status and git diff first; keep what is correct and finish it, or rewrite what is not. Do not discard it blindly.
The roblox-dev plugin skills are available through the Skill tool (roblox-dev:roblox-testing, roblox-dev:roblox-security, roblox-dev:roblox-datastores, roblox-dev:roblox-performance, roblox-dev:roblox-ui); load the relevant ones when useful.

Package reports (integration notes and open issues from implementers/reviewers):
${JSON.stringify(lotSummary).slice(0, 12000)}
Foundation reports:
${JSON.stringify(foundations.filter(Boolean).map(f => ({ package: f.package, notes: f.integration_notes, open: f.open_issues }))).slice(0, 4000)}

You may edit ANY file now (you are the only engineer running). Tasks:
1. grep -rn "TODO(" src — implement anything left.
2. Resolve every integration note (wiring between services, signals, remotes, init order, client↔server payload mismatches: verify each FireClient payload against the client handler that reads it).
3. Write tests/specs/Boot.spec.luau: boot the full server; join 12 players (some Roblox friends via h:makeFriends) in one server; move them with h:moveTo through zones over hundreds of h:step ticks so they catch Nebbies, cut each other's lines, parade at their own gates, buy upgrades and do a Supernova through remotes; time-travel with the shared Clock to trigger weather, Great Comet (pickup, steal, bank), Beacon Night and Starfall Saturday; respawn and leave/rejoin some players and verify data persisted; assert no signal errors, no warnings, no "Infinite yield".
4. Write tests/specs/ClientGame.spec.luau: boot the full client (h:createRemotes) and drive it with realistic server payloads (DataSnapshot, WorldSnapshot, PathStream buffers, LineEvent, WildEvent, SnipEvent, EventState, Banner, Feedback, Celebrate), open every panel, press every HUD button, step frames; assert no errors and that rendering creates/pools parts.
5. Fix every bug these tests reveal (in any file), keeping all specs meaningful.
6. ./scripts/check.sh must pass end to end, including EconomyPacing.
Return the structured report (package = "integration").`, { label: 'intégration', phase: 'Intégration', schema: IMPL_SCHEMA })
log(`Intégration : suite=${integration && integration.full_suite_result}`)
await checkpoint('integration', 'Intégration : jeu complet de bout en bout, tests de démarrage serveur 12 joueurs et client')

// ───────────────────────── Phase 5-6 : QA adversariale + corrections (jusqu'à 2 tours)
const LENSES = [
  { key: 'securite', lens: 'SECURITY & EXPLOITS: every RemoteEvent/RemoteFunction handler (validation of types, NaN/inf, ranges, table sizes, ownership; rate limits), server authority over economy and movement-derived gameplay, MoveCheck holes, comet/snip/catch abuse, code redemption, LiveOps admin checks, anything in ReplicatedStorage that leaks secrets.' },
  { key: 'donnees', lens: 'DATA & ECONOMY INTEGRITY: Schema defaults/migrations/reconcile, profile key ownership, settle/offline math, multiplier M, upgrade/Supernova costs vs GDD tables, Starforge/release/stash rules, double rewards (quests, calendar, codes, comet, beacon, receipts), daily/weekly UTC resets, caps, invariants (never negative, never NaN, integers), save-on-leave/BindToClose paths.' },
  { key: 'robustesse', lens: 'ROBUSTNESS & PERFORMANCE: Roblox lifecycle (PlayerAdded races, existing players, CharacterAdded/respawn/death, leave during yields), nil checks, infinite WaitForChild, StreamingEnabled assumptions, deferred signals, errors inside the 10 Hz tick or render loops that would kill the loop (pcall boundaries), leaks (connections, tables keyed by Player, parts not pooled), per-frame allocations, part/light/Highlight budgets of GDD §12.8.' },
  { key: 'conformite', lens: 'GDD CONFORMANCE, FUN & UX: compare the implementation with docs/02-game-design-document.md MVP scope (§15.1) and FTUE (§3): missing or divergent features and numbers, juice/animation specs of §9 not implemented, mobile UI rules (§10: sizes ≥ 56 px, safe insets, Dash placement), localization gaps (keys missing in FR or EN, hardcoded strings), onboarding clarity, anything that would make the game feel unfinished or not fun.' },
]

let round = 0
const allFixed = []
while (round < 2) {
  round += 1
  phase('QA')
  const reviews = (await parallel([
    ...LENSES.map(l => () => agent(`${COMMON}

ROLE: Adversarial QA reviewer (round ${round}). READ-ONLY: do not modify any file. Your lens:
${l.lens}

Review the whole codebase (src/, tests/) through this lens. Run the tests and tools as needed to confirm problems (you may write throwaway files only under /tmp). Report only REAL, concrete problems with exact file and line, why it is a problem (concrete failure scenario), and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug or GDD core behavior missing; medium = edge-case bug or polish gap; low = nit. Do not report style nits. Be thorough: this game ships to children on phones and must not bug.`, { label: `qa${round}:${l.key}`, phase: 'QA', schema: FINDINGS_SCHEMA })),
    () => agent(`Audit the Roblox/Luau game "Comet Conga" in ${ROOT} (Rojo project: src/server, src/client, src/shared; tests in tests/ run with Lune and are NOT shipped). QA round ${round}. Read docs/04-architecture.md for the intended design, then audit every file under src/ with your full checklist: remote security (validation, rate limits, server authority), DataStore safety (session locking, retries, BindToClose, schema migration, ProcessReceipt idempotence), memory and performance (connection leaks, per-frame allocations, instance pooling, StreamingEnabled), and strict-typing quality. Report only real, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug; medium = edge case or polish gap; low = nit.`, { label: `qa${round}:roblox-reviewer`, phase: 'QA', schema: FINDINGS_SCHEMA, agentType: 'roblox-dev:roblox-reviewer' }),
  ])).filter(Boolean)

  const seen = new Set()
  const findings = []
  for (const r of reviews) for (const f of r.findings) {
    const k = `${f.file}|${(f.title || '').toLowerCase().slice(0, 60)}`
    if (seen.has(k)) continue
    seen.add(k)
    findings.push(f)
  }
  const serious = findings.filter(f => f.severity === 'critical' || f.severity === 'high')
  log(`QA tour ${round} : ${findings.length} constats (${serious.length} critiques/élevés)`)
  const toFix = round === 1 ? findings.filter(f => f.severity !== 'low') : serious
  if (toFix.length === 0) break

  // Regrouper par lot propriétaire (fichiers disjoints entre correcteurs)
  const groups = {}
  for (const f of toFix) {
    let owner = 'divers'
    for (const p of arch.packages) if (p.owned_files.some(of => f.file.endsWith(of) || of.endsWith(f.file))) { owner = p.key; break }
    ;(groups[owner] = groups[owner] || []).push(f)
  }
  phase('Corrections')
  const fixes = (await parallel(Object.entries(groups).map(([owner, list]) => () => agent(`${COMMON}

ROLE: Fixer for the files of package "${owner}" (QA round ${round}). Other fixers handle other packages' files concurrently: only edit the files these findings point to (plus shared registries per the teamwork rules, and new spec files named tests/specs/Fix_${owner}_r${round}*.spec.luau).

Findings to fix (verify each one first; if a finding is wrong, say so and skip it):
${JSON.stringify(list, null, 1).slice(0, 14000)}

For each real finding: write a failing spec reproducing it when testable, fix the code, re-run. Finish with the whole suite and selene. Return the structured report (package = "${owner}"; summary lists each finding as fixed / rejected with reason).`, { label: `fix${round}:${owner}`, phase: 'Corrections', schema: IMPL_SCHEMA })))).filter(Boolean)
  allFixed.push(...fixes.map(x => ({ round, package: x.package, summary: x.summary, open: x.open_issues })))

  const validation = await agent(`${COMMON}

ROLE: Release validator after QA round ${round}. You may edit any file. Run ./scripts/check.sh. If anything fails (format, lint, tests, build, place verification), fix the root cause (never weaken tests) until it passes. Then run the whole suite twice more to detect flaky tests and fix any flakiness. Return the structured report (package = "validation-r${round}").`, { label: `validation${round}`, phase: 'Corrections', schema: IMPL_SCHEMA })
  log(`Validation tour ${round} : ${validation && validation.full_suite_result}`)
  await checkpoint(`qa${round}`, `QA tour ${round} : corrections de sécurité, données, robustesse et conformité au GDD`)
  if (serious.length === 0) break
}

return {
  architecture: { summary: arch.summary, open_questions: arch.open_questions },
  foundations: foundations.filter(Boolean).map(f => ({ package: f.package, summary: f.summary, suite: f.full_suite_result, open: f.open_issues })),
  lots: lotSummary,
  integration: integration && { summary: integration.summary, suite: integration.full_suite_result, open: integration.open_issues },
  qa: allFixed,
}
