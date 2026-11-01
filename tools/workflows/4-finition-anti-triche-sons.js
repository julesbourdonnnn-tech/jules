export const meta = {
  name: 'comet-conga-finition',
  description: 'Comet Conga : vérification indépendante anti-triche et corrections du tour 4, sons officiels Roblox, restes, QA tour 5, rapport final',
  phases: [
    { title: 'Vérification', detail: 'red team anti-triche, revue des corrections du tour 4, recherche de sons officiels' },
    { title: 'Tri', detail: 'regrouper ce qui reste à corriger par fichiers disjoints' },
    { title: 'Corrections', detail: 'un correcteur par groupe' },
    { title: 'Validation', detail: 'check.sh complet + tests instables' },
    { title: 'QA', detail: 'tour 5 ciblé sur tout ce qui n a pas encore été relu' },
    { title: 'Documentation', detail: 'rapport qualité et guide à jour' },
    { title: 'Sauvegarde', detail: 'commit + push' },
  ],
}

const ROOT = '/home/user/jules/roblox-game'
const SCR = '/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad'
const INPUT = `${SCR}/finition-input.json`
const CONSOLE_DOCS = `${SCR}/docs-roblox`
const CREATOR_DOCS = `${SCR}/creator-docs/content/en-us`
const RESOURCES = `${SCR}/roblox-resources`
const BASE = 'c0a97f9'
const UNREVIEWED = 'src/client/Controllers/InputController.luau src/client/Controllers/OnboardingController.luau src/client/Controllers/PanelController.luau src/client/Controllers/VFXController.luau src/client/UI/HUD.luau src/client/UI/Hud/OnboardingPlan.luau src/client/UI/Hud/Widgets.luau src/client/UI/Minimap.luau src/client/UI/Panels/Crew.luau src/client/UI/Panels/Shop.luau src/client/UI/Panels/Upgrades.luau src/client/UI/Panels/Widgets.luau src/client/UI/Root.luau src/client/UI/ScreenFX.luau src/client/Util/Platform.luau src/first/Loading.client.luau src/server/Services/CongaService.luau src/server/Services/QuestService.luau src/shared/Config/Console.luau src/shared/Config/Sounds.luau src/shared/Localization/Strings.luau src/shared/Types.luau'

const COMMON = `You are a senior engineer in a professional Roblox studio finishing the game "Comet Conga" (Luau + Rojo, built entirely in code, no Roblox Studio work, no uploaded assets). The game is implemented and green (./scripts/check.sh: 1396 Lune tests). Four QA rounds are done. This is the final hardening pass before the owner publishes it for children on phones, PC and PlayStation 5.
Repository root: ${ROOT} (git worktree, branch claude/roblox-game). Always cd there first.

SOURCE OF TRUTH
- Game design: docs/02-game-design-document.md (French). Technical contract: docs/04-architecture.md. Console: docs/07-console-ps5.md. Publishing guide: docs/05-guide-publication.md. Quality report: docs/06-rapport-qualite.md.
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
- No state-changing git commands (no commit/add/stash/checkout/reset). Read-only git (git diff, git log, git show) is fine.
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

const TASK = {
  type: 'object',
  properties: {
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    title: { type: 'string' },
    evidence: { type: 'string' },
    fix: { type: 'string' },
  },
  required: ['severity', 'title', 'evidence', 'fix'],
}
const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    groups: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, tasks: { type: 'array', items: TASK } }, required: ['key', 'files', 'tasks'] } },
    rejected: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, reason: { type: 'string' } }, required: ['title', 'reason'] } },
    deferred: { type: 'array', items: { type: 'string' } },
  },
  required: ['groups', 'rejected', 'deferred'],
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
const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    checks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          item: { type: 'string' },
          status: { type: 'string', enum: ['fixed_confirmed', 'still_broken', 'partially_fixed', 'regression', 'not_reproducible'] },
          evidence: { type: 'string' },
        },
        required: ['item', 'status', 'evidence'],
      },
    },
    findings: FINDINGS_SCHEMA.properties.findings,
  },
  required: ['summary', 'checks', 'findings'],
}
const SOUND_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    mapping: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          key: { type: 'string' },
          id: { type: 'string' },
          volume: { type: 'number' },
          pitch: { type: 'number' },
          source_file: { type: 'string' },
          evidence: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['key', 'id', 'source_file', 'evidence', 'confidence'],
      },
    },
    left_empty: { type: 'array', items: { type: 'string' } },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'mapping', 'left_empty', 'notes'],
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

function fixerPrompt(g, label, extra) {
  return `${COMMON}

ROLE: Fixer "${label}". Your assignment covers ONLY these files (other fixers own other files concurrently):
${g.files.map(f => '- ' + f).join('\n')}
plus the shared registries and new spec files named tests/specs/Fix_${label.replace(/[^A-Za-z0-9]/g, '_')}*.spec.luau.

Tasks (each was triaged as real, but re-verify against the current code first; if one is wrong or already fixed, say so and skip it):
${JSON.stringify(g.tasks, null, 1).slice(0, 16000)}
${extra || ''}
For each real task: write a spec that fails before the fix when testable, fix the code at the root cause, re-run. If a correct fix needs a change in a file outside your list, do not edit it: describe it precisely in cross_file_notes. Finish with the whole suite and selene; report honestly.`
}

async function validate(label) {
  return agent(`${COMMON}

ROLE: Release validator (${label}). You are the only engineer running now; you may edit any file. Run ./scripts/check.sh. If anything fails (format, lint, tests, build, place verification), fix the root cause (never weaken tests) until it passes. Then run the whole suite twice more to detect flaky tests and fix the cause of any flakiness (non-deterministic iteration order, real-time dependencies). Also resolve any cross-file notes below that are still needed and safe:
${label}`, { label: `validation:${label.slice(0, 24)}`, phase: 'Validation', schema: VALID_SCHEMA })
}

// ───────────────────────── Vérification indépendante
phase('Vérification')
const verif = await parallel([
  () => agent(`${COMMON}

ROLE: Independent red team, ANTI-CHEAT. READ-ONLY for repository files: put any throwaway spec or script under /tmp (or a tests/specs/Tmp_redteam_*.spec.luau file that you DELETE before finishing) and leave the tree exactly as you found it.
Background: QA round 3 found that standing still for 1 s let a player jump 28 to 58 studs in one tick to snipe or steal the Comet. It was "fixed", then QA round 4 found it again as CRITICAL (MoveCheck's 'burst' verdict ignored by CongaService), plus a HIGH: the Comet burst cap of 1 Epic per player was not enforced within a tick (one player caught 3 to 5 of the 5 Epics). Round 4 fixes were applied but NOBODY has re-audited them. The exact findings and the fixers' reports are in ${INPUT} (keys serious_r3_r4, fixes_r3, fixes_r4); read it.
Your job:
1. For EACH security item among serious_r3_r4, try hard to reproduce the original exploit against the CURRENT code with the Lune harness (Bots, Harness, MoveCheck, CongaService, CometService...). Also try variants the fix may not cover: several smaller jumps in consecutive ticks, jumping right after respawn or after leaving Zen, alternating still/move to reset burst windows, lag-like irregular positions, teleporting along the conga line, catching with a hitbox at the edge, two players colluding, rejoining to reset per-player caps, catching Comet Epics at exactly the same tick from several angles.
2. Check honest players are NOT punished: stairs, slopes, jumping on structures, falling from the floating island edges, respawn, network lag spikes, Dash, the Supernova and Beacon events.
3. Fresh-eyes hunt for any other movement, snip, catch, parade, comet, beacon or Starfall exploit a script kiddie could use.
Report checks (one per original item and per variant, with status and concrete evidence: the spec you ran and its output) and findings (new or remaining problems with exact file/line and precise fix).`, { label: 'verif:anti-triche', phase: 'Vérification', schema: VERIFY_SCHEMA }),

  () => agent(`${COMMON}

ROLE: Independent reviewer of the QA round 4 fixes. READ-ONLY for repository files (throwaway specs under /tmp, or tests/specs/Tmp_verif_*.spec.luau that you DELETE before finishing).
Everything changed since commit ${BASE} (QA round 4 fixes, about 5,300 lines in 46 files) has NOT been reviewed by anyone. Run: git diff ${BASE}..HEAD -- src  and read it all. ${INPUT} has the round 3/4 findings (serious_r3_r4, medium_r4) and what the fixers say they did (fixes_r4, validation_r4_open).
1. For each NON-security item in serious_r3_r4 and medium_r4, confirm the fix really works for a player, end to end (server sends → client shows), with a test you run: stash overflow and limited Starborn Nebbies, the Q7 quest card, loading Retry reachable on controller, Q2/Q5 quest card progress, the "Star Atlas unlocked! 5/150" moment, and every medium.
2. Hunt for REGRESSIONS introduced by the diff: logic errors, nil paths, broken controller navigation (selection holds, PanelNavGuard sinking inputs it should not), leaks (connections never disconnected), UI overlaps at 640x360 / 1280x720 / 1920x1080 TV, French strings longer than their boxes, wrong fallbacks, tests that assert implementation details rather than behaviour.
Report checks (one per item, with status and evidence) and findings (exact file/line, precise fix).`, { label: 'verif:corrections-r4', phase: 'Vérification', schema: VERIFY_SCHEMA }),

  () => agent(`${COMMON}

ROLE: Audio researcher. READ-ONLY for the repository. Problem: the game is nearly silent. src/shared/Config/Sounds.luau holds every sound key; only menu/navigation sounds have ids, taken from sounds published by Roblox itself in its official Feature Packages (github.com/Roblox/resources, packages/feature-packages-core/src/Configs/SharedConstants.lua). Gameplay sounds (Coin, Catch, Bank, LevelUp, Reward, Supernova, Snip, Comet, music...) are empty. GDD §9 (docs/02) describes every sound moment; read it and Sounds.luau to list every key and what it should sound like.
Local copies of Roblox's OFFICIAL repositories are available (no network needed):
- ${RESOURCES} (github.com/Roblox/resources: feature packages, templates, sample code)
- ${CREATOR_DOCS} (github.com/Roblox/creator-docs: official tutorials and API docs)
Find audio asset ids ("rbxassetid://<number>" or SoundId = <number>) that Roblox itself publishes or uses in its official samples, tutorials and templates, and that clearly are AUDIO (used as a Sound.SoundId, AudioPlayer.Asset, in a sounds table, or described as a sound/music in the surrounding text). Images, meshes, animations and decals are NOT acceptable. Read the surrounding code or text for each candidate to know what the sound is (e.g. "coin pickup", "level up", "explosion", "whoosh", "ambient music"). Prefer ids from Roblox-owned packages and templates (they are public and usable in any experience). Only map a key when the sound plausibly fits the moment; otherwise leave the key empty (an empty key is fine, a wrong sound is worse). Suggest volume (0-1) and pitch (to differentiate keys that share an id, at least 15% apart) for each.
Return mapping (key, id in exact "rbxassetid://<number>" form, volume, pitch, source_file relative to the repo root of the copy, evidence = the exact line(s) and what they say, confidence), left_empty (keys with no good candidate) and notes (licensing, anything the owner should listen to before publishing).`, { label: 'sons:recherche', phase: 'Vérification', schema: SOUND_SCHEMA }),

  () => agent(`Audit the Roblox/Luau game "Comet Conga" in ${ROOT} (Rojo project: src/server, src/client, src/shared; tests/ runs under Lune and is NOT shipped). Final audit before publishing. Read docs/04-architecture.md for the intended design. These files were changed by the latest fixes and nobody has reviewed them yet; audit them first and most carefully: ${UNREVIEWED}. Then audit the rest of src/ with your full checklist: remote security (validation, rate limits, server authority), DataStore safety (session locking, retries, BindToClose, schema migration, ProcessReceipt idempotence; also what happens on a LIVE server when DataStores are unavailable), memory and performance (connection leaks, per-frame allocations, pooling), strict-typing quality. Report only real, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug; medium = edge case or polish gap; low = nit.`, { label: 'verif:roblox-reviewer', phase: 'Vérification', schema: FINDINGS_SCHEMA, agentType: 'roblox-dev:roblox-reviewer' }),
])
const [redTeam, verifR4, sounds, reviewer] = verif
log(`Vérification : anti-triche ${redTeam ? redTeam.checks.filter(c => c.status !== 'fixed_confirmed' && c.status !== 'not_reproducible').length : '?'} point(s) encore ouverts ; corrections tour 4 ${verifR4 ? verifR4.checks.filter(c => c.status !== 'fixed_confirmed' && c.status !== 'not_reproducible').length : '?'} ; sons trouvés ${sounds ? sounds.mapping.length : 0}`)

// ───────────────────────── Tri
phase('Tri')
const triage = await agent(`${COMMON}

ROLE: Triage lead for the final hardening pass. READ-ONLY. Build the work list for parallel fixers.
Inputs:
A. Independent anti-cheat red team: ${JSON.stringify(redTeam).slice(0, 14000)}
B. Independent review of round 4 fixes: ${JSON.stringify(verifR4).slice(0, 14000)}
C. roblox-dev auditor: ${JSON.stringify(reviewer).slice(0, 10000)}
D. ${INPUT}: lows_r3, lows_r4 (low findings never fixed), validation_r4_open, console_open.
E. docs/06-rapport-qualite.md lists minor findings still open or "à revérifier" (including full-strength rumble on PS5 and the world-build flag): read it.
F. Audio research result (sound ids from Roblox's official repositories): ${JSON.stringify(sounds).slice(0, 9000)}

Rules:
- Re-verify every item against the CURRENT code before keeping it; reject duplicates, already-fixed items and false positives (with a reason).
- KEEP: every still_broken / partially_fixed / regression item; every critical, high and medium finding; and the lows that matter for a public launch on phone, PC and PS5: data safety (for example a live server falling back to an in-memory store, purchases acknowledged but not saved), anything a player sees or hears (text under 18 px, wrong button hints, overlaps on TV or phones, rumble strength on PS5), contract rule violations (WaitForChild without timeout, extra Heartbeat), budgets.
- SOUNDS: make one dedicated group that fills src/shared/Config/Sounds.luau from F (only ids with high or medium confidence), records the provenance of each id in a comment next to it, deliberately replaces the Contract.spec rule "sons : toutes les clés du §9 existent et sont vides par défaut" with a rule that every id is either "" or exactly "rbxassetid://<digits>" AND has a provenance comment (state this explicitly in the task: the owner asked for an animated, fun game, and a silent build fails that), and checks the audio code plays nothing and errors nothing when an id is empty or fails to load, respects the sfx/music settings, Zen mode and reduced motion where relevant, and does not stack the same sound more than a few times per frame.
- DEFER (do not implement, list in deferred): the owner's open design questions (touch snip radius, VIP badge above head, camera under menus on phones, GDD numbers, Starfall featured species zones, Comet reward size, quest card pulsing) — keep current behaviour.
- Group tasks by DISJOINT file sets (a file belongs to exactly one group), at most 6 groups, each with the list of files it may edit. Put spec-only changes with the code they test.`, { label: 'tri', phase: 'Tri', schema: TRIAGE_SCHEMA })

const groups = (triage && triage.groups || []).filter(g => g.tasks && g.tasks.length && g.files && g.files.length)
log(`Tri : ${groups.reduce((n, g) => n + g.tasks.length, 0)} tâches en ${groups.length} groupes, ${triage ? triage.rejected.length : 0} rejetées, ${triage ? triage.deferred.length : 0} reportées (questions de design)`)

// ───────────────────────── Corrections
phase('Corrections')
const soundExtra = `\nAUDIO RESEARCH (ids found in Roblox's official repositories, with evidence; local copies in ${RESOURCES} and ${CREATOR_DOCS} if you need to re-check a line):\n${JSON.stringify(sounds).slice(0, 12000)}\n`
const fixes = (await parallel(groups.map((g, i) => () => agent(
  fixerPrompt(g, `fin-${g.key}`, g.files.some(f => f.includes('Sounds')) ? soundExtra : ''),
  { label: `fix:${g.key}`, phase: 'Corrections', schema: FIX_SCHEMA })))).filter(Boolean)
const v1 = await validate(`after the final hardening fixes. Cross-file notes from fixers: ${JSON.stringify(fixes.flatMap(x => x.cross_file_notes || [])).slice(0, 8000)}`)
log(`Validation finition : ${v1 && v1.tests_passed} tests, check=${v1 && v1.check_passed}`)
await checkpoint('finition', 'Finition : anti-triche revérifié, sons officiels Roblox, restes des tours 3 et 4')

// ───────────────────────── QA tour 5+ (ciblé sur ce qui n'a jamais été relu)
const LENSES = [
  { key: 'securite', lens: 'SECURITY & EXPLOITS: every RemoteEvent/RemoteFunction handler, movement anti-cheat (MoveCheck burst/speed/hover/noclip) and how CongaService/CometService act on its verdicts, honest players never punished (stairs, slopes, island edges, respawn, lag), comet/snip/catch/parade abuse, purchases and receipts, codes, admin commands.' },
  { key: 'donnees', lens: 'DATA & ECONOMY INTEGRITY: profiles, save-on-leave, BindToClose, live-server DataStore outages, double or lost rewards, receipts, pass revocation, caps, invariants (never negative/NaN, integers).' },
  { key: 'joueur', lens: 'PLAYER EXPERIENCE ON PS5 AND PHONE: walk through the first session (GDD §3) twice, once with only a DualSense on a TV (docs/07-console-ps5.md: PlayStation glyphs, every screen reachable with D-pad + Cross + Circle, readable at 3 m, TV-safe area, chat off, haptics moderate) and once on a 640x360 phone in French. Also listen with your eyes: every GDD §9 sound moment now plays the right Config/Sounds key, nothing too loud, nothing spammed. Report anything blocked, unreadable, silent, spammy or awkward.' },
]
const qaLog = []
let round = 4
while (round < 6) {
  round += 1
  phase('QA')
  const reviews = (await parallel([
    ...LENSES.map(l => () => agent(`${COMMON}

ROLE: Adversarial QA reviewer (round ${round}). READ-ONLY: do not modify repository files (throwaway files only under /tmp). Your lens:
${l.lens}

Start with what has never been reviewed: git diff ${BASE}..HEAD -- src (QA round 4 fixes and the final hardening fixes), then the rest of the codebase through your lens. Run tests and tools as needed to confirm problems. Report only REAL, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug or GDD core behavior missing; medium = edge-case bug or polish gap a player could notice; low = nit. No style nits. Do not report the owner's open design questions (touch snip radius, VIP badge, camera under menus, GDD numbers, Starfall zones, Comet reward size, quest card pulsing).`, { label: `qa${round}:${l.key}`, phase: 'QA', schema: FINDINGS_SCHEMA })),
    () => agent(`Audit the Roblox/Luau game "Comet Conga" in ${ROOT} (Rojo project: src/server, src/client, src/shared; tests/ is Lune-only and NOT shipped). QA round ${round}, final. Read docs/04-architecture.md, then audit src/ with your full checklist, starting with the most recently changed files: ${UNREVIEWED}, plus src/shared/Config/Sounds.luau and the client audio code. Report only real, concrete problems with exact file and line, a concrete failure scenario and the precise fix. Severity: critical = crash/data loss/exploit/core loop broken; high = visible bug; medium = edge case or polish gap; low = nit.`, { label: `qa${round}:roblox-reviewer`, phase: 'QA', schema: FINDINGS_SCHEMA, agentType: 'roblox-dev:roblox-reviewer' }),
  ])).filter(Boolean)

  const seen = new Set()
  const findings = []
  for (const r of reviews) for (const f of r.findings) {
    const file = f.file.replace(ROOT + '/', '')
    const k = `${file}|${(f.title || '').toLowerCase().slice(0, 50)}`
    if (seen.has(k)) continue
    seen.add(k)
    findings.push({ ...f, file })
  }
  const toFix = findings.filter(f => f.severity !== 'low')
  const serious = findings.filter(f => f.severity === 'critical' || f.severity === 'high')
  log(`QA tour ${round} : ${findings.length} constats, ${toFix.length} à corriger (${serious.length} critiques/élevés)`)
  qaLog.push({ round, total: findings.length, toFix: toFix.length, serious: serious.length, seriousTitles: serious.map(f => `${f.file}: ${f.title}`), lows: findings.filter(f => f.severity === 'low').map(f => `${f.file}: ${f.title}`) })
  if (toFix.length === 0) break

  const byFile = {}
  for (const f of toFix) (byFile[f.file] = byFile[f.file] || []).push(f)
  const buckets = []
  const area = f => f.startsWith('src/server/') ? 'serveur' : f.startsWith('src/client/UI') ? 'ui' : f.startsWith('src/client/') ? 'client' : 'partage'
  for (const f of Object.keys(byFile).sort()) {
    const a = area(f)
    let b = buckets.find(x => x.area === a && x.files.length < 4)
    if (!b) { b = { area: a, files: [], tasks: [] }; buckets.push(b) }
    b.files.push(f)
    b.tasks.push(...byFile[f])
  }
  phase('Corrections')
  const rf = (await parallel(buckets.map((b, i) => () => agent(fixerPrompt(b, `r${round}-${b.area}-${i}`), { label: `fix${round}:${b.area}-${i}`, phase: 'Corrections', schema: FIX_SCHEMA })))).filter(Boolean)
  qaLog[qaLog.length - 1].fixes = rf.map(x => ({ group: x.group, fixed: x.fixed, rejected: x.rejected, open: x.open_issues }))
  const v = await validate(`after QA round ${round}. Cross-file notes from fixers: ${JSON.stringify(rf.flatMap(x => x.cross_file_notes || [])).slice(0, 8000)}`)
  qaLog[qaLog.length - 1].validation = v && { tests: v.tests_passed, check: v.check_passed, flaky: v.flaky, open: v.open_issues }
  log(`Validation tour ${round} : ${v && v.tests_passed} tests, check=${v && v.check_passed}`)
  await checkpoint(`qa${round}`, `QA tour ${round} : corrections finales`)
  if (serious.length === 0 && toFix.length <= 3) break
}

// ───────────────────────── Documentation
phase('Documentation')
const docs = await agent(`${COMMON}

ROLE: Technical writer. You may edit docs/, README.md and .claude/skills/roblox-publish/SKILL.md only (no code changes). The owner is French-speaking and NOT a programmer: clear, simple French.
1. Update docs/06-rapport-qualite.md: run ./scripts/check.sh and report the new result and test counts; add a section "Finition" with: the independent anti-cheat red team (what was tried, what was confirmed fixed, what was fixed now), the independent review of the round 4 fixes, the sounds added (which moments now have sound, from which official Roblox source, which stay empty, and that the owner should listen to them in Studio before publishing), the QA rounds below, and refresh the list of minor findings still open (re-check each against the code). Keep the owner's open design questions.
   Red team: ${JSON.stringify(redTeam && { summary: redTeam.summary, checks: redTeam.checks }).slice(0, 5000)}
   Round 4 review: ${JSON.stringify(verifR4 && { summary: verifR4.summary, checks: verifR4.checks }).slice(0, 4000)}
   Sounds research: ${JSON.stringify(sounds && { summary: sounds.summary, left_empty: sounds.left_empty, notes: sounds.notes }).slice(0, 2500)}
   Triage: ${JSON.stringify(triage && { kept: groups.map(g => ({ key: g.key, tasks: g.tasks.map(t => t.severity + ': ' + t.title) })), deferred: triage.deferred }).slice(0, 5000)}
   Fixes: ${JSON.stringify(fixes.map(x => ({ group: x.group, fixed: x.fixed, open: x.open_issues }))).slice(0, 6000)}
   QA rounds: ${JSON.stringify(qaLog).slice(0, 6000)}
2. Update docs/05-guide-publication.md where needed: a short "Sons" section (they are official Roblox sounds already wired; how to change one in src/shared/Config/Sounds.luau if the owner does not like it), and anything the fixes changed for publishing. Check every path you mention exists.
3. Update the README status section (tests count, sounds).
Return a short summary of what you wrote.`, { label: 'documentation', phase: 'Documentation' })
await checkpoint('docs', 'Documentation finale : rapport qualité, guide de publication, README')

return {
  redTeam: redTeam && { summary: redTeam.summary, checks: redTeam.checks.map(c => `${c.status}: ${c.item}`), findings: redTeam.findings.map(f => `${f.severity}: ${f.title}`) },
  verifR4: verifR4 && { summary: verifR4.summary, checks: verifR4.checks.map(c => `${c.status}: ${c.item}`), findings: verifR4.findings.map(f => `${f.severity}: ${f.title}`) },
  reviewer: reviewer && reviewer.findings.map(f => `${f.severity}: ${f.file}: ${f.title}`),
  sounds: sounds && { summary: sounds.summary, mapped: sounds.mapping.map(m => `${m.key} ${m.id} (${m.confidence})`), left_empty: sounds.left_empty, notes: sounds.notes },
  triage: triage && { kept: groups.map(g => ({ key: g.key, tasks: g.tasks.map(t => `${t.severity}: ${t.title}`) })), rejected: triage.rejected.length, deferred: triage.deferred },
  fixes: fixes.map(x => ({ group: x.group, fixed: x.fixed, rejected: x.rejected, open: x.open_issues })),
  validation: v1,
  qa: qaLog,
  docs,
}
