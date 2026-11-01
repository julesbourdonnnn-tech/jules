export const meta = {
  name: 'comet-conga-polish',
  description: 'Comet Conga : tri des restes QA → corrections par lot → console PS5 → QA tour 3+ jusqu à épuisement → guide de publication et rapport qualité',
  phases: [
    { title: 'Tri', detail: 'vérifier et regrouper les restes du tour 2 et les notes' },
    { title: 'Corrections', detail: 'un correcteur par groupe de fichiers disjoints' },
    { title: 'Console', detail: 'PS5 : manette DualSense, interface TV, icônes PlayStation' },
    { title: 'QA', detail: '7 angles adversariaux dont console, jusqu à épuisement' },
    { title: 'Validation', detail: 'check.sh complet + détection des tests instables' },
    { title: 'Documentation', detail: 'guide de publication, rapport qualité, README' },
    { title: 'Sauvegarde', detail: 'commit + push' },
  ],
}

const ROOT = '/home/user/jules/roblox-game'
const LEFTOVERS = '/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/followup-input.json'

const COMMON = `You are a senior engineer in a professional Roblox studio finishing the game "Comet Conga" (Luau + Rojo, built entirely in code, no Roblox Studio work, no uploaded assets). The game is implemented and green (./scripts/check.sh: 1048 Lune tests). This is the polish and hardening phase before publishing to children on phones.
Repository root: ${ROOT} (git worktree, branch claude/roblox-game). Always cd there first.

SOURCE OF TRUTH
- Game design: docs/02-game-design-document.md (French). Technical contract: docs/04-architecture.md (module APIs, payloads, ownership, §16 decisions, §17 economy tuning log).
- Project skills: .claude/skills/{roblox-luau-engineering, roblox-security-datastore, roblox-ui-juice, roblox-qa-testing, roblox-game-design}/SKILL.md. roblox-qa-testing documents the Lune harness, Bots, Wire and ApiAudit.
- The roblox-dev plugin skills are available through the Skill tool (roblox-dev:roblox-security, roblox-dev:roblox-datastores, roblox-dev:roblox-performance, roblox-dev:roblox-ui, roblox-dev:roblox-testing, roblox-dev:luau-strict-typing); load the relevant ones when useful.

TOOLS (in ~/.cargo/bin): stylua, selene, lune, rojo.
- Format: ~/.cargo/bin/stylua <files> ; Lint: ~/.cargo/bin/selene src (0 errors, 0 warnings)
- Tests: ~/.cargo/bin/lune run tests/run -- <filter> (substring of a spec path); whole suite: ~/.cargo/bin/lune run tests/run
- Full gate: ./scripts/check.sh

CODE RULES
- --!strict in every src module; typed public APIs; comments in French, identifiers in English.
- task.wait/spawn/delay/defer only. Server authority: validate every remote payload and rate-limit with RateLimit.allow; never trust client values.
- Lifecycle: players already present, PlayerRemoving cleanup, nil/respawning characters, client WaitForChild always with a timeout.
- Time through the shared Clock module. All player-facing text through Localization keys with BOTH English and French. Numbers from src/shared/Config/*.
- Visuals client-side only; decorative parts anchored and non-colliding; pool instances; respect GDD §12.8 budgets.

TEAMWORK RULES
- Other engineers may edit this tree concurrently: only modify the files your assignment names, plus the shared registries src/shared/Localization/Strings.luau, src/shared/Remotes.luau, src/shared/Config/Sounds.luau (Read right before each small targeted Edit; never rewrite them) and new spec files you create.
- No state-changing git commands (no commit/add/stash/checkout/reset).
- Never delete or weaken existing tests to make them pass.`

const ATTRIB = (args && args.attribution) || ''  // lignes d'attribution des commits, passées par args.attribution

async function checkpoint(label, message) {
  return agent(`You are a release helper. In ${ROOT} run exactly, in order:
1) ~/.cargo/bin/stylua src tests   (formatting only)
2) git add -A
3) git commit -m "${message}" -m "${ATTRIB}"   (if there is nothing to commit, skip to the end)
4) git push origin claude/roblox-game   (if it fails because of the network, retry up to 4 times waiting 2, 4, 8, 16 seconds)
Do not change any other file. Return one line: the new commit hash and whether the push succeeded.`, { label: `sauvegarde:${label}`, phase: 'Sauvegarde', effort: 'low' })
}

const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    groups: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          key: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          tasks: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
                title: { type: 'string' },
                evidence: { type: 'string' },
                fix: { type: 'string' },
              },
              required: ['severity', 'title', 'evidence', 'fix'],
            },
          },
        },
        required: ['key', 'files', 'tasks'],
      },
    },
    rejected: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, reason: { type: 'string' } }, required: ['title', 'reason'] } },
    design_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['groups', 'rejected', 'design_questions'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    group: { type: 'string' },
    summary: { type: 'string' },
    fixed: { type: 'array', items: { type: 'string' } },
    rejected: { type: 'array', items: { type: 'string' } },
    spec_files: { type: 'array', items: { type: 'string' } },
    full_suite_result: { type: 'string' },
    cross_file_notes: { type: 'array', items: { type: 'string' } },
    open_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['group', 'summary', 'fixed', 'rejected', 'spec_files', 'full_suite_result', 'cross_file_notes', 'open_issues'],
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

const VALID_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    check_passed: { type: 'boolean' },
    tests_passed: { type: 'number' },
    fixes_made: { type: 'array', items: { type: 'string' } },
    flaky: { type: 'array', items: { type: 'string' } },
    open_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'check_passed', 'tests_passed', 'fixes_made', 'flaky', 'open_issues'],
}

function fixerPrompt(g, label) {
  return `${COMMON}

ROLE: Fixer "${label}". Your assignment covers ONLY these files (other fixers own other files concurrently):
${g.files.map(f => '- ' + f).join('\n')}
plus the shared registries and new spec files named tests/specs/Fix_${label.replace(/[^A-Za-z0-9]/g, '_')}*.spec.luau.

Tasks (each was triaged as real, but re-verify against the current code first; if one is wrong or already fixed, say so and skip it):
${JSON.stringify(g.tasks, null, 1).slice(0, 16000)}

For each real task: write a spec that fails before the fix when testable, fix the code at the root cause, re-run. If a correct fix needs a change in a file outside your list, do not edit it: describe it precisely in cross_file_notes. Finish with the whole suite and selene; report honestly.`
}

async function validate(label) {
  return agent(`${COMMON}

ROLE: Release validator (${label}). You are the only engineer running now; you may edit any file. Run ./scripts/check.sh. If anything fails (format, lint, tests, build, place verification), fix the root cause (never weaken tests) until it passes. Then run the whole suite twice more to detect flaky tests and fix the cause of any flakiness (non-deterministic iteration order, real-time dependencies). Also resolve any cross-file notes below that are still needed and safe:
${label}`, { label: `validation:${label.slice(0, 20)}`, phase: 'Validation', schema: VALID_SCHEMA })
}

// ───────────────────────── Tri des restes
phase('Tri')
const triage = await agent(`${COMMON}

ROLE: Triage lead. READ-ONLY: do not modify any file in the repository.
Read ${LEFTOVERS}. It holds (a) medium/low findings from QA round 2 that were not fixed and (b) integration notes and open issues written by implementers, reviewers and fixers during the build. Many notes may already be resolved by later work.
For EVERY item: check it against the current code (read the files, grep, run targeted tests if useful). Keep only items that are still real and worth fixing before launch (bugs, exploits, data risks, broken or missing GDD behavior, onboarding/UX gaps, perf budget breaches, cross-package wiring left undone by a fixer that could not edit another package's file). Merge duplicates.
Then group the kept items into at most 6 groups with DISJOINT file sets (no file in two groups), each group coherent (e.g. server economy/data, server conga/movement, server events/social/products, client world rendering, client HUD/onboarding, client panels). List every file a fix will need to touch in that group's files.
Put rejected items (stale, already fixed, wrong, pure nit) in rejected with a one-line reason. Put pure design decisions that need the game owner (not engineering bugs) in design_questions, written so a non-technical French-speaking owner can answer.`, { label: 'tri', phase: 'Tri', schema: TRIAGE_SCHEMA })

const groups = (triage && triage.groups || []).filter(g => g.tasks && g.tasks.length)
log(`Tri : ${groups.reduce((n, g) => n + g.tasks.length, 0)} tâches réelles en ${groups.length} groupes, ${(triage && triage.rejected || []).length} rejetées`)

// ───────────────────────── Corrections des restes
const leftoverFixes = (await parallel(groups.map(g => () => agent(fixerPrompt(g, `restes-${g.key}`), { label: `fix0:${g.key}`, phase: 'Corrections', schema: FIX_SCHEMA })))).filter(Boolean)
const crossNotes0 = leftoverFixes.flatMap(f => f.cross_file_notes || [])
const v0 = await validate(`after leftover fixes. Cross-file notes from fixers: ${JSON.stringify(crossNotes0).slice(0, 8000)}`)
log(`Validation restes : ${v0 && v0.tests_passed} tests, check=${v0 && v0.check_passed}`)
await checkpoint('restes', 'Polissage : restes du tour 2 de QA et notes d intégration corrigés')

// ───────────────────────── Console PlayStation 5
const CONSOLE_DOCS = '/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/docs-roblox'
const CONSOLE_BRIEF = `CONSOLE CONTEXT: the game owner will play Comet Conga on a PlayStation 5 with a DualSense controller, on a TV seen from about 3 m. Roblox's official docs are downloaded in ${CONSOLE_DOCS} (production_publishing_console-guidelines.md, input_gamepad.md, production_promotion_content-maturity.md): read them. Key official rules: build for the 10-foot experience (relative sizes, scale up when GuiService.ViewportDisplaySize is Enum.DisplaySize.Large; GuiService:IsTenFootInterface() is the only guaranteed console check; keep important UI inside the TV-safe area); every interactive element reachable with the four directions + select + back; key actions in few moves, with shortcut buttons; NO chat window on console (TextChatService ChatWindowConfiguration disabled when on console); show button icons matching the device (UserInputService:GetImageForKeyCode returns PlayStation glyphs on PlayStation, never hardcode Xbox letters like "X"/"Y"/"LB" because ButtonX is the Square button on a DualSense); haptics in moderation; audio feedback on UI navigation. Conventional mapping: ButtonA (Cross) confirm/jump, ButtonB (Circle) back/cancel, Thumbstick1 move, Thumbstick2 camera, R2/L2 primary actions, L1/R1/ButtonX/ButtonY secondary actions. The game already has base gamepad support (ContextActionService bindings in InputController, Selectable buttons with NextSelection* in HUD and panels, GuiService.SelectedObject in PanelController, key caps in HUD, HapticService in VFXController, GDD §10.4 table): build on it, do not rewrite it.`

const CONSOLE_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    groups: {
      type: 'array',
      items: {
        type: 'object',
        properties: { key: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, tasks: { type: 'array', items: { type: 'string' } } },
        required: ['key', 'files', 'tasks'],
      },
    },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'groups', 'open_questions'],
}

phase('Console')
const consoleDesign = await agent(`${COMMON}

${CONSOLE_BRIEF}

ROLE: Console lead (design + shared foundation). You are the only engineer running now; you may edit any file.
1. Audit the current controller-only and TV experience end to end in the code: InputController, PanelController, HUD and Hud/*, Panels/*, OnboardingController and Hud/OnboardingPlan (prompts that say tap/touch or show keyboard keys), Root (scaling, safe insets), Banners, Toast, Minimap, ScreenFX, src/first/Loading.client.luau, VFXController haptics, AudioController, chat. List every gap versus the official rules above.
2. Write docs/07-console-ps5.md (French): the console design: full DualSense mapping table (gameplay, menus, pings, minimap, cheer, Supernova hold-to-confirm with a controller, shop and purchases), 10-foot scaling rule (exact UIScale factor for Large displays and minimum text sizes), TV-safe margins, glyph strategy (UserInputService:GetImageForKeyCode with a text fallback), navigation rules for every screen (default selection, B behavior, L1/R1 tabs, wrap-around), haptic map, navigation sounds, chat window rule, and how each rule is tested. Update GDD §10.4 table to match (PlayStation names alongside generic KeyCodes).
3. Implement the shared foundation yourself, with specs: a client platform/glyph module (console detection via GuiService:IsTenFootInterface() guarded by pcall, ViewportDisplaySize, preferred input, glyph image or text for a KeyCode, change signal), the harness support it needs in tests/harness (mock IsTenFootInterface, ViewportDisplaySize, GetImageForKeyCode, TextChatService.ChatWindowConfiguration, a way to boot the client as a console with only a gamepad), and the chat window rule. Check every new class/property against ApiAudit (the Roblox reflection database bundled with Lune); if an API is missing there, use an older stable equivalent.
4. Split the remaining implementation into at most 3 groups with DISJOINT file sets (for example: input/controllers/audio/haptics; HUD/onboarding/banners/toast/minimap/loading/root; panel controller and panels), each with precise tasks referencing docs/07. Each group must include specs proving its screens work with a gamepad only (every interactive element reachable through the NextSelection graph or Roblox's default directional selection, B closes, glyphs are PlayStation on console).
Run the whole suite and selene before returning.`, { label: 'console:conception', phase: 'Console', schema: CONSOLE_SCHEMA })

const consoleGroups = (consoleDesign && consoleDesign.groups || []).filter(g => g.files && g.files.length && g.tasks && g.tasks.length)
log(`Console : ${consoleGroups.length} groupes à implémenter`)
const consoleImpl = (await parallel(consoleGroups.map(g => () => agent(`${COMMON}

${CONSOLE_BRIEF}

ROLE: Console implementer "${g.key}". Read docs/07-console-ps5.md first (the console design written by the console lead) and use the shared platform/glyph module and harness support it added. Your assignment covers ONLY these files (other implementers own other files concurrently):
${g.files.map(f => '- ' + f).join('\n')}
plus the shared registries and new spec files named tests/specs/Console_${g.key.replace(/[^A-Za-z0-9]/g, '_')}*.spec.luau.

Tasks:
${g.tasks.map(t => '- ' + t).join('\n')}

Keep touch, keyboard and mouse behavior unchanged (existing specs must stay green). If a correct change needs a file outside your list, describe it in cross_file_notes. Finish with the whole suite and selene; report honestly.`, { label: `console:${g.key}`, phase: 'Console', schema: FIX_SCHEMA })))).filter(Boolean)
const vc = await validate(`after console PS5 support. Cross-file notes from console implementers: ${JSON.stringify(consoleImpl.flatMap(x => x.cross_file_notes || [])).slice(0, 8000)}`)
log(`Validation console : ${vc && vc.tests_passed} tests, check=${vc && vc.check_passed}`)
await checkpoint('console', 'Console PS5 : manette DualSense, interface 10 pieds, icônes PlayStation, navigation complète')

// ───────────────────────── QA jusqu'à épuisement
const LENSES = [
  { key: 'securite', lens: 'SECURITY & EXPLOITS: every RemoteEvent/RemoteFunction handler (types, NaN/inf, ranges, table sizes, ownership, rate limits), movement anti-cheat (MoveCheck: speed, hover, noclip, teleport) versus honest players (stairs, slopes, standing on structures or heads, respawn, lag), comet/snip/catch/parade abuse, purchases and receipts, codes, admin commands.' },
  { key: 'donnees', lens: 'DATA & ECONOMY INTEGRITY: Schema defaults/migrations/reconcile, newer-schema guard, profile key ownership, settle/offline math, upgrade/Supernova costs vs Config, Starforge/stash rules, double or lost rewards (quests at UTC reset, calendar, codes, comet, beacon, Starfall, receipts, pass revocation), caps, invariants (never negative/NaN, integers), save-on-leave, rejoin races, BindToClose.' },
  { key: 'robustesse', lens: 'ROBUSTNESS & PERFORMANCE: startup error isolation (one failing service/controller must not freeze the game or the loading screen), Roblox lifecycle races, pcall boundaries in the 10 Hz tick and render loops, leaks (connections, Player-keyed tables, unpooled parts), per-frame allocations, network bytes per second and peaks (GDD §12.8), particle/part/light budgets.' },
  { key: 'experience', lens: 'FIRST-SESSION PLAYER EXPERIENCE (a 9-year-old on a phone, French or English): walk through GDD §3 FTUE minute by minute in the code (loading screen, Q1-Q7 onboarding, first catch, first parade, first upgrade, first Supernova, return screen). Find anything confusing, blocked, silent (no feedback/juice when something happens), unreadable on a small screen (§10: touch targets ≥ 56 px, safe insets, overlaps with joystick/jump/Dash), untranslated, or not fun. Also check every GDD §9 juice spec is really wired.' },
  { key: 'console', lens: `PLAYSTATION 5 WITH A DUALSENSE ONLY (no touch, no keyboard, no mouse; TV at 3 m; GuiService:IsTenFootInterface() true, ViewportDisplaySize Large). ${CONSOLE_BRIEF} Read docs/07-console-ps5.md, then walk through the whole game with only the controller: loading screen, onboarding Q1-Q7 (prompts must show PlayStation glyphs, never "tap", keyboard keys or Xbox letters), catching, Dash, pings, cheer, minimap, every panel, tab and button (reachable by D-pad/stick selection, Circle goes back, default selection set when a screen opens), shop and purchase prompts, Supernova hold-to-confirm, return screen, settings. Check text readable at TV distance, nothing important in the TV-unsafe border, chat window disabled on console, haptics not overused, navigation sounds. Report anything unreachable, unclear, unreadable or awkward.` },
  { key: 'conformite', lens: 'GDD CONFORMANCE: compare the implementation with docs/02-game-design-document.md MVP scope (§15.1), every system of §4 and every number, plus docs/04-architecture.md payload contracts: missing or divergent features, dead code paths (functions never called, signals never fired or never subscribed), client handlers for payloads the server never sends and vice versa.' },
]

let round = 2
const qaLog = []
let dry = 0
while (round < 4) {
  round += 1
  phase('QA')
  const reviews = (await parallel([
    ...LENSES.map(l => () => agent(`${COMMON}

ROLE: Adversarial QA reviewer (round ${round}). READ-ONLY: do not modify repository files (throwaway files only under /tmp). Your lens:
${l.lens}

Review the whole codebase (src/, tests/) through this lens. Run tests and tools as needed to confirm problems. Report only REAL, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug or GDD core behavior missing; medium = edge-case bug or polish gap a player could notice; low = nit. No style nits. Earlier rounds already fixed many issues, so look deeper than the obvious.`, { label: `qa${round}:${l.key}`, phase: 'QA', schema: FINDINGS_SCHEMA })),
    () => agent(`Audit the Roblox/Luau game "Comet Conga" in ${ROOT} (Rojo project: src/server, src/client, src/shared; tests/ runs under Lune and is NOT shipped). QA round ${round}. Read docs/04-architecture.md for the intended design, then audit every file under src/ with your full checklist: remote security (validation, rate limits, server authority), DataStore safety (session locking, retries, BindToClose, schema migration, ProcessReceipt idempotence), memory and performance (connection leaks, per-frame allocations, pooling, StreamingEnabled), strict-typing quality. Report only real, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug; medium = edge case or polish gap; low = nit.`, { label: `qa${round}:roblox-reviewer`, phase: 'QA', schema: FINDINGS_SCHEMA, agentType: 'roblox-dev:roblox-reviewer' }),
  ])).filter(Boolean)

  const seen = new Set()
  const findings = []
  for (const r of reviews) for (const f of r.findings) {
    const k = `${f.file.replace(ROOT + '/', '')}|${(f.title || '').toLowerCase().slice(0, 50)}`
    if (seen.has(k)) continue
    seen.add(k)
    findings.push({ ...f, file: f.file.replace(ROOT + '/', '') })
  }
  const toFix = findings.filter(f => f.severity !== 'low')
  const serious = findings.filter(f => f.severity === 'critical' || f.severity === 'high')
  log(`QA tour ${round} : ${findings.length} constats, ${toFix.length} à corriger (${serious.length} critiques/élevés)`)
  qaLog.push({ round, total: findings.length, toFix: toFix.length, serious: serious.length, lows: findings.filter(f => f.severity === 'low').map(f => `${f.file}: ${f.title}`) })
  if (toFix.length === 0) { dry += 1; break }

  // Regroupement par fichier : un correcteur par ensemble de fichiers disjoints (au plus 6)
  const byFile = {}
  for (const f of toFix) (byFile[f.file] = byFile[f.file] || []).push(f)
  const files = Object.keys(byFile).sort()
  const buckets = []
  const area = f => f.startsWith('src/server/') ? 'serveur' : f.startsWith('src/client/UI') ? 'ui' : f.startsWith('src/client/') ? 'client' : 'partage'
  for (const f of files) {
    const a = area(f)
    let b = buckets.find(x => x.area === a && x.files.length < 4)
    if (!b) { b = { area: a, files: [], tasks: [] }; buckets.push(b) }
    b.files.push(f)
    b.tasks.push(...byFile[f])
  }
  phase('Corrections')
  const fixes = (await parallel(buckets.map((b, i) => () => agent(fixerPrompt(b, `r${round}-${b.area}-${i}`), { label: `fix${round}:${b.area}-${i}`, phase: 'Corrections', schema: FIX_SCHEMA })))).filter(Boolean)
  qaLog[qaLog.length - 1].fixes = fixes.map(x => ({ group: x.group, fixed: x.fixed, rejected: x.rejected, open: x.open_issues }))
  const cross = fixes.flatMap(x => x.cross_file_notes || [])
  const v = await validate(`after QA round ${round}. Cross-file notes from fixers: ${JSON.stringify(cross).slice(0, 8000)}`)
  qaLog[qaLog.length - 1].validation = v && { tests: v.tests_passed, check: v.check_passed, flaky: v.flaky, open: v.open_issues }
  log(`Validation tour ${round} : ${v && v.tests_passed} tests, check=${v && v.check_passed}`)
  await checkpoint(`qa${round}`, `QA tour ${round} : corrections (sécurité, données, robustesse, expérience joueur, conformité)`)
  if (serious.length === 0 && toFix.length <= 3) break
}

// ───────────────────────── Documentation
phase('Documentation')
const docs = await agent(`${COMMON}

ROLE: Technical writer and release manager. You may edit docs/, README.md and .claude/skills/roblox-publish/SKILL.md only (no code changes).
The game owner is French-speaking and NOT a programmer. Write in clear, simple French.

1. Create docs/05-guide-publication.md: a step-by-step guide to go from this repository to a published Roblox game. Cover: installing Roblox Studio and the tools (Rojo via rokit/aftman or the Rojo Studio plugin), building build/Game.rbxl with rojo build -o build/Game.rbxl (or rojo serve + the Studio plugin for live sync), opening and testing in Studio (Play solo, then Test > Local Server with several players), publishing to Roblox, enabling Studio API access to DataStores for testing, creating the 6 game passes and 6 developer products in the Creator Hub with the exact names and prices from src/shared/Config/Monetization.luau then pasting their ids there, setting admin UserIds in the admin config and launch codes, max players 12, the maturity/content questionnaire, genre, icon and thumbnails (what to show), localization (FR/EN already in the game), a pre-launch checklist and a post-launch checklist (analytics events in src/server/Util/Analytics.luau, what metrics to watch: D1/D7 retention, session length, payer conversion). Check every file path and config name you mention exists.
   The owner wants to play on PlayStation 5: add a dedicated "Jouer sur PlayStation 5" section based ONLY on the official docs downloaded in ${CONSOLE_DOCS} and on docs/07-console-ps5.md: content maturity (Maturity & Compliance questionnaire is required for consoles), enabling console among the experience's playable devices, testing with Studio's Controller Emulator before the real PS5, how the owner finds and launches the game from the Roblox app on PS5, and the DualSense controls table. Mark clearly as "à vérifier" any step those docs do not confirm (for example exact menu names in Studio/Creator Hub, whether a private or unrated game can be joined on PS5, purchases on PlayStation).
2. Create docs/06-rapport-qualite.md: the quality report. Gather the facts yourself: run ./scripts/check.sh and report its result; count specs and tests; summarize the build process (architecture contract, foundations, 6 lots each implemented then reviewed, integration with a 12-player server simulation and a recorded-session client replay, QA rounds with security/data/robustness/experience/conformance/roblox-dev auditor lenses) using git log; list what is verified automatically and, honestly, what can only be verified in Roblox Studio (real rendering, real physics, real DataStores and purchases, server tick time with 12 real players, text fit, particle look, phone ergonomics) with a concrete manual test plan for Studio. Include these QA round results: ${JSON.stringify(qaLog).slice(0, 6000)}. Include these open design questions for the owner: ${JSON.stringify((triage && triage.design_questions) || []).slice(0, 3000)}.
3. Update README.md: keep the pitch, update quick start, add a short status section (playable on phone, PC and PlayStation 5 / Xbox controller, tests count, what remains manual before publishing) linking docs/05, docs/06 and docs/07.
4. Make sure .claude/skills/roblox-publish/SKILL.md is consistent with docs/05.
Return a short summary of what you wrote.`, { label: 'documentation', phase: 'Documentation' })
await checkpoint('docs', 'Documentation : guide de publication, rapport qualité, README à jour')

return {
  triage: triage && { kept: groups.map(g => ({ key: g.key, tasks: g.tasks.map(t => `${t.severity}: ${t.title}`) })), rejected: triage.rejected.length, design_questions: triage.design_questions },
  leftovers: leftoverFixes.map(f => ({ group: f.group, fixed: f.fixed, rejected: f.rejected, open: f.open_issues })),
  validation0: v0,
  console: { design: consoleDesign && consoleDesign.summary, open: consoleDesign && consoleDesign.open_questions, impl: consoleImpl.map(x => ({ group: x.group, fixed: x.fixed, open: x.open_issues })), validation: vc },
  qa: qaLog,
  docs,
}
