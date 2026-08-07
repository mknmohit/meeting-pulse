# Handoff: what to give an implementing agent

Read this first if you are coordinating the build. It tells you which files each agent needs and in what order the work is dispatched.

---

## The short answer

**Always give these four. They are the contract.**

| File | Why it is mandatory |
|---|---|
| `docs/03-implementation-plan.md` | The build itself. Tasks, code, SQL, tests, gates |
| `docs/02-meetingpulse-spec.md` | What the product must do and must never do |
| `PRODUCT.md` | Who it is for and which constraints outrank convenience |
| `docs/copy/deck.md` | Every user-facing string. Agents must not improvise text |

**Add these two when the agent is doing design work or is likely to "simplify" something.**

| File | Why |
|---|---|
| `docs/04-plan-audit-and-resolutions.md` | The 40 defects already found and fixed. Stops an agent reintroducing one |
| `docs/01-spec-audit-report.md` | Why the spec looks the way it does. Mostly useful for architecture decisions |

Nothing else. There is no hidden context.

---

## The one-line prompt

For a single agent doing everything:

> Read `PRODUCT.md`, `docs/02-meetingpulse-spec.md`, `docs/03-implementation-plan.md`, `docs/04-plan-audit-and-resolutions.md`, and `docs/copy/deck.md` in that order. Then execute `docs/03-implementation-plan.md` from §3 (Phase 0), stopping at each gate. Do not skip Spike S1. When in doubt, fail closed.

---

## Splitting across agents

The plan is built to be split. Phases 2, 3, and 6 run alongside the critical path once Phase 0 is done.

### Agent 1 — Foundation (Phase 0)

**Give:** the four core files.
**Scope:** plan §3 in full.
**Done when:** all four CI jobs are green on a pull request from a clean clone with no repository secrets configured.

This agent goes first and alone. Everything else depends on the scaffolds it creates.

### Agent 2 — Detection spikes (Phase 1) ⛔ Gates G1 and G2

**Give:** the four core files, plus `01-spec-audit-report.md` so it understands why the Chrome question matters.
**Scope:** plan §6.
**Done when:** `docs/decisions/0001-meet-detection-strategy.md` and `0002-slack-detection-strategy.md` exist, each naming a fallback rung and concrete selectors.

**This is a human-in-the-loop phase.** The agent writes the tooling and analyses the dumps, but someone has to actually join a Meet call and start a Slack huddle on the real machine. Budget half a day of your own time here. It is the cheapest half-day in the project.

Nothing downstream of the critical path starts until this reports.

### Agent 3 — Database (Phase 2) ⛔ Gate G3

**Give:** the four core files, plus `04-plan-audit-and-resolutions.md`.
**Scope:** plan §5.
**Done when:** `supabase test db` passes, including all fourteen negative RLS tests and the concurrency tests.

Include the resolutions document for this one specifically. Nine of the forty defects were SQL, and several of the fixes look like they could be simplified until you know what they are guarding against. An agent that has not read it will very reasonably decide that `mp_throttle_check` does not need `FOR UPDATE`.

Runs in parallel with Agents 2 and 4.

### Agent 4 — Core logic (Phase 3)

**Give:** the four core files.
**Scope:** plan §7.
**Done when:** 95% coverage on `MPCore`, all 32+ decision-table cases green, and `MPCore` imports nothing but the standard library.

The easiest phase to verify and the one most worth getting exactly right. Runs in parallel with everything.

### Agent 5 — Detection (Phase 4)

**Give:** the four core files, plus `04-plan-audit-and-resolutions.md`, plus both decision documents from Agent 2.
**Blocked by:** Gates G1 and G2.
**Scope:** plan §8.
**Done when:** all eleven detector tests in §8.7 pass, especially the four marked non-negotiable.

The hardest phase. `AXRunLoopHost` (§8.2) is the piece most likely to be got wrong, because attaching an `AXObserver` inside a Swift actor compiles cleanly and then silently never fires. Make sure the agent writes the live integration test for it rather than only unit tests.

### Agent 6 — Owner services (Phase 5)

**Give:** the four core files, plus `04-plan-audit-and-resolutions.md`.
**Blocked by:** Gate G3.
**Scope:** plan §9.
**Done when:** the coalescing test, the redaction test, and the three-state Keychain tests pass.

### Agent 7 — Viewer (Phase 6) ⛔ Gate G4

**Give:** the four core files. The copy deck matters more here than anywhere else.
**Blocked by:** Gate G3.
**Scope:** plan §10, built against §4, the design contract.
**Done when:** the design detector reports no findings, contrast is measured on the rendered plates, the greyscale screenshot proves each state is distinguishable, and the built HTML contains the seed key `950bbeef`.

Tell this agent explicitly that §4 is binding and that the refused list in §4.4 is not a style preference. Design agents default to cards and coloured dots, and both are banned here for reasons the section explains.

Runs in parallel with Agents 5 and 6.

### Agent 8 — Owner app (Phase 7)

**Give:** the four core files.
**Blocked by:** Phases 4 and 5.
**Scope:** plan §11.
**Done when:** the app builds, signs, notarises, staples, and passes `spctl`.

### Agent 9 — Acceptance (Phase 8)

**Give:** the four core files, plus `04-plan-audit-and-resolutions.md`.
**Scope:** plan §12.
**Done when:** all 30 acceptance scenarios recorded, performance measured, the privacy capture attached, and the pre-publication checklist complete.

**Also human-in-the-loop.** Scenarios 9b, 13b, 21, 22, 23, 25, 26, 28, and 30 need a real machine, a real phone, and real meetings. The agent can prepare the harness and record results; it cannot join a call for you.

---

## Dispatch order

```
Agent 1 (Phase 0)
      │
      ├──────────────┬──────────────┐
      ▼              ▼              ▼
  Agent 2        Agent 3        Agent 4
  (spikes)       (database)     (core logic)
   ⛔ G1 G2        ⛔ G3
      │              │              │
      ▼              ├──────┬───────┘
  Agent 5            ▼      ▼
  (detection)    Agent 6  Agent 7
      │          (owner   (viewer)
      │           services) ⛔ G4
      └──────┬───────┘
             ▼
         Agent 8 (owner app)
             ▼
         Agent 9 (acceptance)
```

---

## Five things to tell every agent

Paste these into every prompt. They are the rules that no amount of documentation enforces on its own.

1. **Fail closed.** Never render `available` from an absence of evidence. Never invent a config value. Never swallow an Accessibility error. Never report a sync that did not happen.

2. **Never map `unknown` to `inactive`.** If you find yourself writing that, stop. It is how the product tells her he is free while he is in a meeting, and it is the one failure it does not recover from.

3. **Do not simplify a guard you do not understand.** Several fixes in this plan look redundant. `docs/04-plan-audit-and-resolutions.md` names what each one prevents. Read it before deleting anything.

4. **All user-facing text comes from `docs/copy/deck.md`.** No improvised microcopy.

5. **Record decisions this plan did not make for you** in `docs/decisions/`, with reasoning.

---

## Two things an agent cannot do

Be realistic about this when you plan the schedule.

**Spike S1 and S2** need someone to join a real Meet call and start a real Slack huddle while the dump tool runs. An agent can build `axdump`, run the diffs, and write the decision document, but it cannot be in the meeting.

**The acceptance matrix** needs a real Mac, a real phone, real sleep and wake cycles, and real network drops. About a third of the thirty scenarios are hands-on.

Everything else is fully automatable.

---

## If you only hand over one file

Give `docs/03-implementation-plan.md`. It is self-contained enough to build from, and it cites the others where they matter. You will get a worse result than handing over all four, because the agent will improvise copy and will not know which constraints are load-bearing, but it will build something that works.
