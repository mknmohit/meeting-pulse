# Meeting Pulse — Plan Audit and Resolutions

**Audited:** `03-implementation-plan.md` v1.0 (2 133 lines)
**Method:** independent adversarial review against SQL correctness, Swift 6 / macOS platform behaviour, state-machine edge cases, operational lifecycle, testability, and phase ordering.
**Result:** 40 defects. 8 blocking, 31 major, 1 minor. **All 40 are resolved in `03-implementation-plan.md` v2.0.**

This document is the traceability record. Each row names the defect, the resolution, and where the resolution lives.

---

## Blocking

### B1 — The native app cannot authenticate once Turnstile is enabled
Supabase applies its captcha to every auth endpoint, `signInAnonymously` included. Only the web viewer can render a Turnstile widget, so the Mac app could never sign in, and neither first run nor recovery would work. The v1 plan enabled Turnstile and never noticed it had locked out the owner.

**Resolution.** The Mac app renders the Turnstile widget once, in a `WKWebView` hosting a small bundled HTML page, and returns the token through a script message handler. The owner solves it exactly twice in the app's life: at first registration and at a recovery rebind. Token refreshes need no captcha. Plan §7.2 (`TurnstileGate`), §10.1.

---

### B2 — The CI viewer build was designed to fail
`config.ts` rejects any value containing `YOUR_`, and CI copied `.env.example`, which contains exactly those placeholders, before running `astro build`. Phase 0 CI could never be green.

**Resolution.** Two config files with two jobs. `.env.example` keeps human placeholders and is asserted to **fail** the build (the failure is now a test). `.env.ci` is committed with shape-valid, obviously non-production values and is what CI builds against. Plan §3.4, §3.8.

---

### B3 — Phase 0 CI referenced projects that Phase 6 and Phase 2 create
Phase 0 ran `pnpm install`, viewer tests, `astro build`, and `supabase db reset`, but the viewer was not scaffolded until Phase 6 and Supabase was not initialised until Phase 2. `T0.4` also wrote `viewer/src/config.ts` before `pnpm create astro` ran in that directory.

**Resolution.** Phase 0 now scaffolds both: the Astro project and `supabase init` with an empty migrations directory move into Phase 0 as T0.5 and T0.6. Every CI job has something real to run from the first commit. Plan §3.5, §3.6, §3.8.

---

### B4 — A pairing code could be claimed by two viewers at once
`claim_pairing_code` selected the row without `FOR UPDATE`, checked `claimed_at`, then updated unconditionally. Two concurrent transactions could both observe the code unclaimed and both insert a viewer row.

**Resolution.** The claim is now a single atomic statement: `UPDATE pairing_codes SET claimed_at = now() WHERE code_hash = $1 AND claimed_at IS NULL AND revoked_at IS NULL AND expires_at > now() RETURNING device_id`. Zero rows returned means failure. Plan §5.6.

---

### B5 — A failed read left a stale "Free" on screen forever
`effectiveDisplayState` compared `server_now` and `last_seen_at` from the **last successful** response. If every subsequent fetch failed, `server_now` never advanced, so the page never went stale. Malformed timestamps produced `NaN`, and `NaN > 180` is `false`, so a corrupt payload also rendered as fresh.

This is the exact failure the whole product is built to prevent: a confident "Free" while he is in a meeting.

**Resolution.** Age is now `serverAgeAtFetch + monotonicElapsedSinceFetch`, using `performance.now()`. Any non-finite or negative value fails closed to `unavailable`. Plan §9.5, test `freshness.test.ts`.

---

### B6 — Cascading from `auth.users` destroyed the thing recovery was meant to recover
`devices.owner_user_id` referenced `auth.users` with `ON DELETE CASCADE`. Any anonymous-user cleanup would delete the device, its status, its codes, and every viewer pairing, before `rebind_device` could ever run. The recovery mechanism was wired to be destroyed by the event it existed to survive.

**Resolution.** `owner_user_id` is now nullable with `ON DELETE SET NULL`. The device outlives every auth identity, and the recovery hash is the durable authority. Plan §5.3, §5.5.

---

### B7 — The Meet latch converted uncertainty into "Free"
In the idle phase, `strongConfirm == nil` (meaning the tab could not be evaluated) emitted `.inactive`. So an app restart during a backgrounded call, or any startup where the first strong observation was missed, published **Free during a meeting**.

**Resolution.** `Evidence` now separates "scan completed and found no Meet page anywhere" from "could not evaluate". Only the former yields `.inactive`; the latter yields `.unknown`. Plan §8.4, and it is now the first mandatory latch test.

---

### B8 — `AXObserver` had no run loop to deliver callbacks to
`AXObserver` callbacks require the observer's run-loop source to be added to a live `CFRunLoop`. Swift actor tasks resume on arbitrary cooperative-pool threads with no run loop, so "attach an AXObserver in the detector actor" would compile and never fire.

**Resolution.** A dedicated `AXRunLoopHost`: one long-lived `Thread` running a `CFRunLoop`, owning every observer, its sources, retention, PID reattachment, and teardown. It converts callbacks into `Sendable` value events on an `AsyncStream` that actors consume. Plan §8.2.

---

## Major

| # | Defect | Resolution | Plan |
|---|---|---|---|
| M1 | `inet_client_addr()` returns the pooler's address behind Supavisor, so the per-IP throttle either groups every viewer together and locks them all out, or separates nothing | The IP layer is **removed**. Anti-abuse is Turnstile plus the per-user limit plus the global circuit breaker. Rationale recorded in a decision document | §5.6, §5.7 |
| M2 | `FORCE ROW LEVEL SECURITY` silently depends on the definer role holding `BYPASSRLS`, which was never set or tested | `FORCE` is dropped. RLS is enabled with no policies on RPC-only tables, and a migration test asserts `rolbypassrls` on the function owner | §5.4, test `01_rls_negative` |
| M3 | `register_device` was not idempotent under concurrency; two calls raced and one hit a unique-index violation instead of returning the existing id | `pg_advisory_xact_lock(hashtextextended(owner_user_id))` serialises registration per owner | §5.5 |
| M4 | `rebind_device` did not lock its target (two identities could race) and deleted **every** other active device owned by the caller, not just an empty one | Target is locked `FOR UPDATE`. Only a device with zero viewers and no published status is reclaimed; anything else raises `rebind_would_orphan` | §5.6 |
| M5 | A viewer could hold unlimited active pairings and `get_paired_status()` used an unordered `LIMIT 1`, so reads were nondeterministic | Partial unique index caps a viewer at one active pairing; claiming revokes any prior pairing in the same statement; the read is ordered | §5.3, §5.6, §5.7 |
| M6 | "Delete remote data" left the `auth.users` row, its identities, and the throttle row behind | Wording corrected to what it does, throttle rows are deleted, and an operator runbook covers auth cleanup | §5.5, §12.4 |
| M7 | `create_pairing_code` accepted any TTL up to 3 600 s, so a modified client could mint one-hour codes | The parameter is removed. 600 seconds, server-side, not negotiable | §5.5 |
| M8 | PostgreSQL grants `EXECUTE` on new functions to `PUBLIC`; revocation only happened in migration 7, leaving an exposure window between migrations | `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` in migration 1, plus an inline revoke after every `CREATE FUNCTION` | §5.2, §5.5 |
| M9 | The claim path claimed timing indistinguishability it does not have (a missing index lookup is not equivalent to fetching an existing row) | Reworded as response-shape suppression, which is what it actually provides and what actually matters at 50 bits | §5.6 |
| M10 | `SET LOCAL` outside a transaction does not reliably set JWT claims, and the `supabase db execute` loop is not the CLI's test workflow | pgTAP via `supabase test db`, every file wrapped in `BEGIN`/`ROLLBACK`, with committed helpers for creating users and switching identity | §5.8 |
| M11 | The global-throttle test could not reach 100 failures because the IP layer blocked at 20 first | Moot once the IP layer is removed (M1); the test now drives the per-user limit across many users and seeds the global counter directly for the boundary case | §5.8 |
| M12 | The normalization prose said "uppercase, strip, map" while the SQL mapped before stripping. Following the prose deletes `I`, `L`, and `O` instead of mapping them. The SQL test also could not read a JSON file from inside the database | Canonical order fixed and stated once: **uppercase → map confusables → strip**. A generator emits a SQL `VALUES` fixture from the JSON, and all three implementations assert the same SHA-256 over the fixture | §7.3 |
| M13 | `AXUIElement` is a CoreFoundation reference with no `Sendable` guarantee, yet the tree protocol was declared `Sendable` with unconstrained generics | Live AX references never leave `AXRunLoopHost`. Actors receive immutable `AXSnapshot` value types | §8.2, §8.3 |
| M14 | Actor methods are reentrant at `await`, so a slow safety sample could resume after a newer event-driven sample and publish obsolete evidence | One owned sampling task per detector, a monotonically increasing generation counter, and results committed only when the generation still matches | §8.5 |
| M15 | The two-sample settle rule existed in both `MeetLatch` and `DetectionScheduler`, doubling release latency and making Meet and Slack behave differently | Settling lives in exactly one place: the scheduler. Detectors emit raw observations | §8.4, §8.6 |
| M16 | One latch anchor could not represent a second Meet call; closing the anchored window released to inactive even with another call live, and the precedence was undefined | The latch holds a **set** of anchors. Release requires a full rescan finding no confirmable session anywhere | §8.4 |
| M17 | Chrome PWA and profile windows may not resolve under `com.google.Chrome`, and neither appeared in the detector or acceptance tests | Chrome-family bundle identifiers are enumerated, PWA support is declared explicitly by Gate G1, and profile/PWA cases are mandatory tests | §6.3, §8.3, §11.2 |
| M18 | `AXHandleID` was never defined; there is no universally stable AX window identifier | Gate G1 must record the tested anchor identity mechanism. Default is the private `_AXUIElementGetWindow` window number with a documented fallback, and live elements stay inside the AX host | §6.3, §8.2 |
| M19 | Permission revocation and detector resampling were separate triggers, so a stale `.active` could be published after the grant was lost | A permission transition synchronously invalidates all detector evidence and latches **before** any publish | §8.6, §9.2 |
| M20 | Enumerating running applications is not atomic; two simultaneous launches could both proceed or both quit, and the current process was never excluded | `LSMultipleInstancesProhibited` in Info.plist plus an `flock` on a lock file in Application Support. Enumeration is only for the activate-and-exit nicety | §10.1 |
| M21 | `errSecInteractionNotAllowed` from a locked Keychain was indistinguishable from a missing credential, so a transient error could mint a new identity and orphan the device | Three distinct outcomes: `present`, `missing`, `temporarilyUnavailable`. The last one retries and never registers a replacement identity | §7.1 |
| M22 | Nothing required the app to live in `/Applications`; running from a translocated DMG breaks `SMAppService` registration and confuses the TCC grant | First run checks its own path, offers to move itself, and registers the login item only from the final location. In-place same-signature upgrade is an acceptance test | §10.2, §11.2 |
| M23 | A background `LSUIElement` app is subject to App Nap and timer coalescing, which can miss the 15 s, 2 s, and 60 s intervals the whole design assumes | `DispatchSourceTimer` with declared leeway, a scoped `ProcessInfo.beginActivity` assertion, and a four-hour backgrounded release-build acceptance test that measures actual intervals | §8.6, §11.2 |
| M24 | A graceful Quit published nothing, so the viewer showed a stale state for up to 210 s, indistinguishable from a crash | Quit attempts a bounded (2 s) final publish of `unavailable`. Staleness remains the fallback for crashes and force quits | §9.2, §10.3 |
| M25 | Re-arming timers on clock-change notifications does not help when the clock moves **backwards**; overrides and latches would silently extend by hours | All deadlines use `ContinuousClock`. Wall-clock timestamps are kept only for persistence, and a rollback-safe cap is applied after relaunch | §7.4, §8.4 |
| M26 | The described menu (large pairing code, live countdown, text editing, typed confirmation) cannot live in a native-style `MenuBarExtra` | Scene architecture is now explicit: `.menuBarExtraStyle(.menu)` for commands only, with four dedicated `Window` scenes for onboarding, pairing, settings, and recovery | §10.1, §10.4 |
| M27 | `ManualOverrideStore`, `PairingService`, and `RecoveryService` were named in the architecture but had no implementation task | Three new tasks with their own tests: atomic persistence, expiry-task lifecycle, recovery generation and rebind | §7.4, §7.5 |
| M28 | Committed AX fixtures used unsalted 8-hex hashes, which are dictionary-reversible for common labels and collide at 32 bits, and hashing the labels also destroyed the selectors the tests need to exercise | Fixtures use hand-reviewed semantic pseudonyms with an explicit mapping file. Structural labels are preserved verbatim; only human content is replaced | §6.2 |
| M29 | Injecting only the AX tree left `NSRunningApplication`, `AXIsProcessTrusted`, lifecycle notifications, and observers unmockable, so most detector tests were unrunnable | Five injected protocols: `AXElementTree`, `AppDiscovery`, `PermissionProbe`, `AXEventSource`, and `Clock` | §8.3, §8.7 |
| M30 | "One active device per owner" is unenforceable when each Mac is a different anonymous user, so a second Mac silently created a second orphan device | A second Mac is an explicit **transfer**, performed with the recovery phrase. A per-instance nonce lets a superseded Mac learn it lost ownership and stop publishing | §5.5, §7.5, §10.4 |
| M31 | Viewer identity lives only in script-writable storage, which iOS Safari evicts after prolonged non-use, silently breaking a bookmark that still looks fine | Accepted and designed for. The eviction path renders a calm re-pair screen, not an error. Add-to-Home-Screen guidance, a 20-second owner-side re-code flow, and an explicit acceptance test that clears storage | §9.7, §11.2 |
| M32 | No uninstall path, no remote retention policy, no operator runbook, and no answer for a paused free-tier project | `docs/setup/operations.md` covers uninstall, retention, and pausing. The 60 s heartbeat means an active install never lets the project idle into a pause | §12.4 |

---

## Minor

**m1 — Timing-attack language.** See M9. The claim path suppresses response *shape*, not timing. At 50 bits of entropy with a 10-minute window and a global breaker, timing is not the weak link, and the plan no longer implies otherwise.

---

## What this audit did not find

No defect was found in the parts of v1 that came out of the first audit: the ordered reducer, the fail-closed principle, server-assigned timestamps, the RPC-only write path, the minimal viewer projection, the privacy boundary, or the phase gates. Those held up under adversarial review and are carried into v2.0 unchanged in substance.

The one exception is instructive. The reducer was correct, but the **latch** underneath it (B7) quietly fed it a false `.inactive`, which would have produced exactly the failure the reducer was designed to prevent. Correct logic on top of an incorrect input is still a wrong answer. That is why v2.0 pushes the fail-closed rule down into the detector layer rather than trusting the reducer to hold the line alone.
