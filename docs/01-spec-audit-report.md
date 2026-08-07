# Meeting Pulse — Specification Audit Report

**Audited document:** `2026-08-07-meeting-status-design.md` (676 lines, "Meeting Status Companion — Design Specification")
**Audit date:** 2026-08-07
**Auditor scope:** correctness, internal consistency, security, privacy, technical feasibility, implementability by an LLM without human clarification
**Verdict:** Sound product thinking and an unusually disciplined privacy model. **Not implementable as written** — 10 blocking defects, 18 material gaps. All are addressed in `02-meetingpulse-spec.md` (v2.0) and `03-implementation-plan.md`.

---

## Scoring

| Dimension | v1 | v2 (after fixes) | Notes |
|---|---|---|---|
| Product clarity | 9/10 | 9/10 | Scope discipline was already excellent |
| Privacy model | 9/10 | 10/10 | Two leaks closed (override metadata, device id) |
| Security model | 5/10 | 9/10 | Rate limiting was bypassable; identity loss unrecoverable |
| Technical feasibility | 4/10 | 8/10 | Chrome background-tab detection risk was unacknowledged |
| Internal consistency | 6/10 | 10/10 | Reducer precedence was contradictory |
| Implementability by an LLM | 4/10 | 9/10 | Too many "decide during planning" placeholders |
| Operational readiness | 3/10 | 9/10 | No signing, notarization, distribution, or update story |

---

## A. Blocking defects

### A1 — Product naming is inconsistent
The document is titled "Meeting Status Companion". The product is **Meeting Pulse**. Names leak into bundle identifiers, keychain service names, log subsystems, the Cloudflare project, the Supabase project, and user-visible copy; leaving this unresolved guarantees inconsistent artifacts.

**Fix:** Public name `Meeting Pulse`; internal compatibility identifiers remain `MeetingPulse`, including bundle id `com.techdevix.meetingpulse`, log subsystem `com.techdevix.meetingpulse`, keychain service `com.techdevix.meetingpulse.auth`, and repo `meetingpulse`.

---

### A2 — The status reducer rules are contradictory (BLOCKING)
§5.9 lists five rules as an unordered set:

- Rule 1: confirmed active in either source → `busy`
- Rule 3: any required detector permission failure or untrusted observation → `unavailable`
- Rule 4: a manual override supersedes automatic detection

These collide in real, common situations:

| Situation | Rule 1 says | Rule 3 says | Rule 4 says | v1 answer |
|---|---|---|---|---|
| Meet confirmed active, Slack AX tree unreadable | busy | unavailable | — | **undefined** |
| Manual "Set Busy" active, Accessibility revoked | — | unavailable | busy | **undefined** |
| Chrome not running, Slack not running | — | — | — | **undefined** |

Worse, the "fail closed" principle in Goal 10 ("never a guessed `Available`") is violated by the naive reading of rule 3: downgrading a **confirmed busy** to `unavailable` because an *unrelated* source is unreadable produces a *less* safe answer for the viewer, not a safer one. The whole point is that the wife should not call during a meeting; `unavailable` invites her to call and check.

**Fix (v2 §6.4):** a single, ordered, total function. Precedence: `override > confirmed busy > unknown > available`. Written as an explicit decision table with all 4×4 source-pair combinations enumerated, so it is directly testable.

---

### A3 — Chrome background-tab Accessibility exposure is the project's largest technical risk and is unaddressed (BLOCKING)
§5.6 requires confirming an in-call state through "stable call controls or accessibility labels" in the Chrome AX hierarchy, and forbids using the tab title as the sole signal. But the owner's normal behaviour during a Meet call is to **switch to other tabs and other apps**. Chromium does not reliably expose the rendered accessibility tree of non-visible tabs; the `AXWebArea` for a backgrounded Meet tab may vanish entirely from the AX hierarchy.

If that is true on the installed Chrome build, the v1 detector reports "call controls missing" the instant the owner switches tabs. Per §5.5 that becomes `unknown`, per rule 3 that becomes `unavailable`, and the product is useless during the exact moments it exists to cover.

v1 contains no acknowledgement of this, no fallback, and no gate. §11 step 2 ("Prove Accessibility detection") is the right instinct but has no defined success/failure branch — an implementing LLM would build the whole system on an unvalidated assumption.

**Fix (v2 §7.3 + plan Spike S1):** a **latched session model**. Confirmation requires strong in-call evidence while the tab is observable; once confirmed, the detector latches to `active` and maintains the latch on weaker, always-observable liveness evidence (tab strip entry persistence, window persistence, optional corroborating audio-device-in-use signal). Latch release requires positive end evidence or liveness loss. Spike S1 is a hard gate with three pre-declared outcomes and a defined fallback ladder, including an explicit "cut Chrome auto-detection to manual-only" exit. No downstream work starts before S1 reports.

---

### A4 — Anonymous auth identity loss permanently orphans the device (BLOCKING)
§5.10 anchors device ownership to a Supabase **anonymous** `auth.users` row on the Mac. Anonymous identity is only as durable as the locally stored refresh token. It is lost by: Keychain reset, machine re-image, restore-from-backup to new hardware, extended offline period exceeding refresh-token lifetime, or Supabase project anonymous-user cleanup.

When it is lost, the Mac authenticates as a **new** anonymous user. The old `devices` row, and every viewer paired to it, becomes unreachable and un-deletable by anyone. There is no owner email, no password, and no admin path that does not involve the service-role key. v1 offers no recovery.

Since the entire UX promise is "pair once, never think about it again", silent permanent breakage is a product-level failure, not an edge case.

**Fix (v2 §8.6):** a **device recovery secret**. At registration the Mac generates 32 random bytes; only `sha256` is stored server-side. A `rebind_device(recovery_secret)` `SECURITY DEFINER` RPC re-attaches the current anonymous user to the existing device row, preserving all viewer pairings. The secret is stored in the Keychain and is displayable/exportable once from the menu bar as a recovery phrase. Rate-limited identically to pairing claims.

---

### A5 — Pairing rate limiting is trivially bypassable (BLOCKING, security)
§5.10 requires "a small per-viewer attempt limit using the internal `pairing_attempts` table", keyed `viewer_user_id uuid primary key`. Anonymous sign-up is open by definition — an attacker mints a fresh anonymous user per attempt and the limit never binds. The effective protection against online code guessing is therefore **zero**, and v1 also leaves the code alphabet and length undecided (§12), so the entropy floor is undefined too.

Additionally, unrestricted anonymous sign-up is itself an abuse vector: unlimited `auth.users` rows and unlimited `devices` rows on a free-tier project.

**Fix (v2 §8.5):**
1. Code entropy fixed at **50 bits** (Crockford Base32, 10 chars, `XXXXX-XXXXX`), expiry 10 minutes, single use. At 50 bits with a 10-minute window, guessing is infeasible even unthrottled.
2. Three-layer throttle: per-`viewer_user_id` (5 / 15 min), **per-IP** via `inet_client_addr()` (20 / hour), and a **global** failure circuit breaker (100 / hour → claims rejected, owner alerted). Global counter is the layer an anon-user-minting attacker cannot dodge.
3. Cloudflare **Turnstile** captcha required on anonymous sign-in (Supabase Auth native support), which prices the user-minting bypass out.
4. `devices` insert capped at one non-revoked device per `owner_user_id` by a partial unique index.
5. Constant-time-ish claim path: identical response shape and no early return for invalid/expired/claimed/revoked.

---

### A6 — Viewer staleness is computed against the client's clock (BLOCKING)
§5.11 assigns `last_seen_at` with database `now()` (correct) but the viewer then "derives `Status unavailable` when the last heartbeat is older than three minutes" using `Date.now()`. Browser clocks are routinely wrong by minutes, and a phone that has just changed timezone or resumed from sleep can be off by hours.

Failure modes are both directions and both bad: a fast client clock shows a permanent false `Status unavailable`; a slow client clock shows a **stale `Available` indefinitely**, which is precisely the guessed-Available that Goal 10 forbids.

**Fix (v2 §9.3):** every status read returns `server_now` from the same statement. The viewer computes `age = server_now − last_seen_at` entirely from server-sourced values, and derives its own "last checked" label from a monotonic local elapsed timer since the fetch, never from wall-clock arithmetic against a server timestamp.

---

### A7 — The viewer read leaks override metadata and the device identifier (privacy)
§5.10 puts `override_mode` and `override_expires_at` in `current_status` and grants paired viewers a **select policy on the row**. So the viewer can read that the owner *manually forced* Busy, and until when.

This breaks the product's social contract. "Busy" should be indistinguishable whether it came from a detected meeting or from the owner pressing Set Busy for 30 minutes; otherwise the viewer learns "he is not actually in a meeting, he just doesn't want to talk", which is more socially loaded than the meeting data the spec carefully refuses to send. It also directly contradicts §6.12's intent that device identifiers not be exposed to the viewer.

**Fix (v2 §8.4):** viewers get **no table select grant at all**. Reads go through `get_paired_status()` (`SECURITY DEFINER`, `STABLE`) returning exactly `{ display_name, state, call_okay, last_seen_at, server_now, schema_version }`. Override fields stay owner-only. RLS on `current_status` is deny-all for viewers as defense in depth.

---

### A8 — App Sandbox / distribution constraints are unstated and constrain the whole build (BLOCKING)
Inspecting another process's AX tree via `AXUIElementCopyAttributeValue` requires the app to be **outside the App Sandbox** and to hold the Accessibility TCC grant. v1 never states this, which means an implementer could plausibly enable the sandbox (Xcode's default for a new macOS app), ship, and discover at runtime that every AX call returns `kAXErrorAPIDisabled`.

Consequences that must be decided up front, not discovered:
- **No Mac App Store distribution is possible.** Distribution must be Developer ID + notarization + stapled DMG.
- The Accessibility TCC grant is keyed to the **code-signing identity and bundle id**. Changing either, or shipping an ad-hoc/unsigned build, silently invalidates the user's grant and the app looks broken after an update.
- Local development builds and release builds have different signatures, so both need separate grants during development.

**Fix (v2 §5.4, plan Phase 0/7):** App Sandbox **off**, Hardened Runtime **on**, `LSUIElement = true`, Developer ID Application signing with a stable identity, `notarytool` submission + `stapler`, DMG distribution, Sparkle deferred to Phase 2 with an explicit "signing identity must never change" constraint recorded in `SECURITY.md`.

---

### A9 — No minimum macOS version, no packaging, no update strategy
§12 defers "exact minimum macOS deployment target" to planning, but the target choice determines whether `MenuBarExtra` (13+), `SMAppService` (13+), Swift 6 strict concurrency defaults, and Observation (`@Observable`, 14+) are usable. Every one of those is load-bearing in the v1 architecture, so the choice is not deferrable.

**Fix (v2 §5.2):** **macOS 14.0** minimum. Universal 2 binary (`arm64` + `x86_64`) in the first release — the marginal cost is one build setting and it removes a whole class of "works on my machine" reports. Xcode 16.x / Swift 6.0 toolchain pinned in `.xcode-version` and CI.

---

### A10 — `not_available` semantics are underspecified for the all-absent case
§5.5 says `not_available` "is treated as inactive only when the source is genuinely not running". §5.9 rule 2 says "confirmed inactive in **all applicable** sources yields `available`" — but never defines "applicable". If Chrome and Slack are both closed, is the set of applicable sources empty, and is the state therefore `available`, or is it undefined-and-therefore-`unavailable`?

This is not academic: it is the state of the machine every morning before the owner opens anything, so getting it wrong makes the product wrong at rest.

**Fix (v2 §6.4):** if the app is healthy and holds Accessibility permission, all sources absent → **`available`** (we positively know he is not in a Meet call or a Slack Huddle). Only *unreadable* sources produce `unknown`. Also renames the observation case (see C5) to eliminate the `unavailable`/`not_available` confusion that produced this ambiguity.

---

## B. Material gaps

| # | Gap | Impact | Fix location |
|---|---|---|---|
| B1 | Override persistence across app restart / crash undefined | Quit during a "Busy 2h" override silently reverts to auto on relaunch | v2 §6.5 — persisted to `Application Support`, re-validated against server time on launch |
| B2 | No republish scheduled at override expiry | Override lapses locally but the viewer keeps showing the old state until the next 60 s heartbeat | v2 §6.5 — a dedicated expiry `Task` fires a recompute + immediate publish |
| B3 | `schema_version` written but never read | Forward-compat column with no forward-compat behaviour | v2 §9.4 — viewer renders `Status unavailable` + "update needed" on unknown version |
| B4 | Multiple devices per owner, device reset, re-pair flows undefined | Second Mac silently creates a second orphan device row | v2 §8.2 — one active device per owner (partial unique index), explicit reset flow |
| B5 | No data deletion path | Cannot honour "delete everything about me"; also blocks a public release | v2 §8.7 — `delete_device()` cascades; menu bar "Reset & delete remote data" |
| B6 | No log rotation, retention, redaction test, or diagnostics export | §6.9 mandates redaction but nothing enforces or verifies it | v2 §10.3 — OSLog + 7-day rotating file, redaction unit test, sanitized diagnostics export |
| B7 | `rotate_pairing_codes` / `revoke_viewer` / `revoke_all_viewers` appear in prose but not in the API surface | Ambiguous RPC contract | v2 §8.4 — full RPC table with signatures, security mode, and error codes |
| B8 | No index or constraint plan | Full scans and unenforced invariants | plan §4.2 — indexes and CHECK constraints enumerated in migrations |
| B9 | Memory/CPU targets have no measurement method | Untestable acceptance criteria | v2 §11.4 — `footprint`/`sample` procedure, 10-minute idle window, pass/fail |
| B10 | Viewer a11y, dark mode, reduced motion, offline copy unspecified | Primary user is a non-technical person on a phone | v2 §9.5 — WCAG 2.2 AA, prefers-color-scheme, prefers-reduced-motion, offline banner |
| B11 | Retry policy has no numbers | "bounded exponential backoff" is not implementable | v2 §9.2 — 1 s base, ×2, 60 s cap, full jitter, infinite retries for heartbeat / 5 attempts for user-initiated |
| B12 | Code alphabet/length deferred | Blocks the security argument in A5 | v2 §8.5 — Crockford Base32, 10 chars, 50 bits |
| B13 | Sleep/wake, network path, and TCC-change observation APIs unnamed | Each needs a specific, non-obvious API | v2 §7.5 — `NSWorkspace` sleep/wake notifications, `NWPathMonitor`, 5 s TCC poll (no KVO exists for AXIsProcessTrusted) |
| B14 | No single-instance guard | Two copies = duplicate publishes, flapping state | v2 §5.5 — `NSRunningApplication` bundle-id check at launch |
| B15 | `pairing_attempts` window reset semantics undefined | Unimplementable as written | v2 §8.5 — fixed 15-minute tumbling window, reset on first attempt after window end |
| B16 | No secret scanning despite an open-source goal | The one failure mode that is irreversible once pushed | plan §7.3 — `gitleaks` in CI + pre-commit, `.gitignore` allowlist test |
| B17 | License undecided | Blocks public release | v2 §5.6 — **MIT** |
| B18 | `og.techdevix.com` repeated as a recommendation inside a config-driven spec | Invites hardcoding | v2 §5.6 — documentation example only; build fails if `PUBLIC_STATUS_ORIGINS` is unset |

---

## C. Editorial / clarity

- **C1** §1 lists `Busy - call okay` alongside the three states, implying four states. The model is **3 states × 1 boolean**. Restated in v2 §4.1.
- **C2** "duration picker" never enumerates its options. v2 §6.5 fixes the presets: 15 m, 30 m (default), 45 m, 1 h, 2 h, 4 h, Until I clear it.
- **C3** §4.3 step 2 omits the Turnstile challenge now required by A5. Added.
- **C4** §9 acceptance says "within five seconds" but §5.8 idle sampling is 15 s; the worst case is 15 s + publish latency when no AX event fires. v2 §11.3 states both bounds explicitly.
- **C5** `unavailable` (published state) and `not_available` (source observation) differ by one underscore and mean different things — this is the direct cause of A10. Observation case renamed **`sourceAbsent`**; observation enum is now `active | inactive | unknown | sourceAbsent`.
- **C6** §8's 80 MB / 1% targets are reasonable; only the measurement method was missing (B9).
- **C7** §5.10's `viewers` table lacks an index on `viewer_user_id`, which is the lookup direction the viewer RPC actually uses. Added in the plan.
- **C8** §4.2 lists "Refresh and publish status now" ambiguously; v1 §4.3 later clarifies the owner/viewer refresh asymmetry well. v2 moves that clarification up to first mention.

---

## D. What v1 got right (preserved unchanged in v2)

These decisions are correct and were **not** modified — an implementer should treat them as fixed:

1. **Fail-closed status semantics.** Never guess `Available`. This is the correct default for the product's actual purpose.
2. **No Chrome extension, no Slack bot, no OAuth, no calendar.** Correctly identifies that official APIs cannot give one instant cross-platform signal, and that the local-agent approach is the only one that covers arbitrary Meet links.
3. **Publish state, never content.** No titles, URLs, participants, media, or screenshots. The data model is genuinely minimal.
4. **No Realtime.** Change-triggered writes + 60 s heartbeat + focused-tab 30 s polling is the right cost/complexity trade for one viewer.
5. **Visibility- and focus-gated polling.** Correct for battery and for free-tier quota.
6. **Native Swift over Electron/Tauri.** Correct given the AX dependency and the 80 MB target.
7. **Astro static + Cloudflare Pages.** Correctly sized; no server runtime needed.
8. **RPC-mediated writes with server-assigned timestamps.** Correct — never trust a client clock for `last_seen_at`.
9. **Hashed, short-lived, single-use pairing codes.** Correct primitive (the *throttling* around it was the defect, not the primitive).
10. **Generic claim-failure messaging.** Correct oracle suppression.
11. **Detector interface with a 4-case observation and a "never coerce unknown to inactive" rule.** Correct and forward-compatible.
12. **`screen_sharing` column reserved and always `null` in the MVP.** Correct forward-compat without scope creep.
13. **Config injection with `.example` files and no silent fallback.** Correct, and rare to see specified this precisely.
14. **The incremental build order in §11.** Preserved; v2 only inserts the spike gates.

---

## E. Changes made in v2 — index

| v2 section | Change | Source finding |
|---|---|---|
| Whole doc | Public name renamed to Meeting Pulse; internal identifiers fixed | A1 |
| §4.1 | State model restated as 3 states × 1 flag | C1 |
| §5.2 | macOS 14.0, Universal 2, Xcode/Swift pinning | A9 |
| §5.4 | Sandbox off, Hardened Runtime, Developer ID, notarization, stable identity | A8 |
| §5.5 | Single-instance guard | B14 |
| §5.6 | MIT license; `PUBLIC_STATUS_ORIGINS` mandatory, no default | B17, B18 |
| §6.4 | Ordered reducer + full 4×4 decision table | A2, A10 |
| §6.5 | Override persistence, expiry timer, duration presets | B1, B2, C2 |
| §7.2 | Observation enum renamed `sourceAbsent` | C5 |
| §7.3 | Latched Chrome session model + S1 gate + fallback ladder | A3 |
| §7.5 | Sleep/wake, network, TCC-change observation APIs named | B13 |
| §8.2 | One active device per owner; reset flow | B4 |
| §8.4 | Full RPC surface; viewer read via `get_paired_status()` only | A7, B7 |
| §8.5 | Code entropy, 3-layer throttle, Turnstile, window semantics | A5, B12, B15 |
| §8.6 | Device recovery secret + `rebind_device()` | A4 |
| §8.7 | `delete_device()` erasure path | B5 |
| §9.2 | Concrete retry/backoff numbers | B11 |
| §9.3 | `server_now` staleness | A6 |
| §9.4 | `schema_version` handling | B3 |
| §9.5 | Viewer a11y / theming / offline | B10 |
| §10.3 | Logging, rotation, redaction test, diagnostics export | B6 |
| §11.3–11.4 | Latency bounds restated; perf measurement method | C4, B9 |

---

## F. Residual risks after v2 (accepted, with owners)

| Risk | Likelihood | Impact | Mitigation | Gate |
|---|---|---|---|---|
| Chrome does not expose sufficient background-tab liveness signal | Medium | High — kills auto-detection for Meet | Latch model; fallback ladder; manual-only exit | **S1 (hard gate)** |
| Slack's Electron AX tree exposes no stable huddle signal | Medium | Medium — Slack becomes manual-only | Independent detector; can ship Meet-only | **S2 (hard gate)** |
| Chrome/Slack UI update breaks selectors | High over time | Medium | All matching isolated to one file per detector; reports `unknown`, never a wrong `available`; diagnostic code names the missing signal | Ongoing |
| Accessibility TCC grant lost after an app update | Low | Medium | Stable signing identity; startup permission check with recovery UI | Phase 7 |
| Supabase anonymous auth policy changes | Low | High | Recovery secret + rebind makes migration to real auth non-breaking | Phase 2 |
| Free-tier limits exceeded | Very low | Low | ~1.4 k writes/day, ~2.9 k reads/day at full usage — orders of magnitude under free tier | Phase 5 |

---

## G. Recommendation

Proceed to implementation using `02-meetingpulse-spec.md` as the authoritative specification and `03-implementation-plan.md` as the build order.

**Do not start Phase 3 or later until Spike S1 has reported.** S1 is cheap (roughly half a day of AX-tree dumping) and it is the single assumption on which the product's viability rests. Building the reducer, backend, and viewer before S1 risks a complete rewrite of the detection layer or an unbuildable product.
