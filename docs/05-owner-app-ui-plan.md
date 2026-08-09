# Meeting Pulse owner app: UI implementation plan

Build plan for giving the macOS owner app a real interface. Today every
function lives in a menu bar pull-down. After this plan, the menu bar keeps six
items and everything else lives in a window called **The Station**.

This document is the contract. It is written so an implementing agent can build
the whole surface without opening a design tool and without inventing a single
string, colour, duration, or layout value.

**Read first, in this order:** `PRODUCT.md`, `docs/02-meetingpulse-spec.md`,
`docs/copy/deck.md`, then this file. Where this file and `PRODUCT.md` disagree,
`PRODUCT.md` wins and you file the conflict rather than resolving it yourself.

---

## Table of contents

| § | Section |
|---|---|
| 1 | What exists today |
| 2 | Scope: what moves, what stays, what is new |
| 3 | The direction contract |
| 4 | Design system (`MPUI` tokens) |
| 5 | Package and scene architecture |
| 6 | The mast: the permanent instrument |
| 7 | Section specs |
| 8 | Onboarding window |
| 9 | The reduced menu bar |
| 10 | Motion specification |
| 11 | State model: `PulseStore` and `PulseActions` |
| 12 | Copy: every new string |
| 13 | Accessibility |
| 14 | Xcode project changes |
| 15 | Task list with acceptance criteria |
| 16 | Testing |
| 17 | Risks, gotchas, and open decisions |
| 18 | Definition of done |

---

## 1. What exists today

Everything in the owner app is one file: `mac-app/MeetingPulse/MeetingPulseApp.swift`,
1,112 lines. It contains the `App`, the app delegate, the runtime, the model,
the launch coordinator, the menu bar view, the hand-drawn menu bar icon, and
five near-identical `VStack` windows.

### 1.1 Current surfaces

| Surface | Lines | What it is |
|---|---|---|
| `MenuBarView` | 722-792 | A flat `NSMenu`. 13 items, two submenus of 7 |
| `HeartThreadMenuIcon` | 794-929 | An `NSImage` drawn with `NSBezierPath`, colour-coded status dot |
| `OnboardingWindow` | 931-956 | Four paragraphs and one button |
| `PairingWindow` | 958-1035 | Code, copy buttons, rotate, revoke |
| `SettingsWindow` | 1037-1063 | Display name field, launch at login toggle |
| `RecoveryWindow` | 1065-1091 | Recovery phrase and a copy button |
| `DiagnosticsWindow` | 1093-1112 | Three `LabeledContent` rows |

Every window is `VStack(alignment: .leading, spacing: 16)` inside
`.padding(24)` with a fixed `.frame(width: 420...460)`. There is no navigation,
no empty state, no loading state, no error state, no hover state, and no motion
except an 0.18s crossfade on the menu bar image.

### 1.2 Data the UI cannot currently see

These already exist in the packages and never reach the model. The new UI needs
all of them, so wiring them is part of this plan, not a follow-up.

| Value | Lives in | Currently |
|---|---|---|
| `SchedulerReading.meet` / `.slack` | `MPDetection.DetectionScheduler` | Read in `OwnerRuntime.start()`, logged, discarded |
| `SchedulerReading.accessibilityGranted` | same | Same |
| `EffectiveStatus.reason` | `MPCore.StatusReducer` | Logged, discarded |
| `SyncCoordinator.currentState` (`.idle` / `.retrying` / `.superseded`) | `MPSync` | Only `.idle` is checked, once |
| `SyncCoordinator.lastSuccessfulSync` | `MPSync` | Never read |
| `StatusTransport.listViewers()` | `MPSync` | Never called anywhere in the app |
| `PermissionCoordinator.changes` | `MPSupport` | Stream created, never consumed |
| `NetworkMonitor.changes` | `MPSupport` | Type exists, never instantiated |
| `InstallLocation.isValid()` | `MPSupport` | Checked once at launch, result thrown away |
| `AppLaunchCoordinator.state` | app target | Not observable, never rendered |

### 1.3 Adjacent defects this plan must fix

These are not stylistic. The new UI displays values that are currently wrong or
absent, so leaving them broken would ship a lying interface.

**D1. The heartbeat never starts.** `SyncCoordinator.startHeartbeat(interval:payload:)`
exists and is never called. `PRODUCT.md` requires a 60-second owner heartbeat,
and the viewer marks anything older than 180 seconds as stale. Without the
heartbeat, a quiet owner goes stale after three minutes and the page reads
"Meeting status unavailable" while he sits at his desk. Fix in T14.

**D2. `connectionLine` is initialised to a failure.** `OwnerAppModel.connectionLine`
starts as `"Can't reach the server. Retrying."` before any request is made, so
the menu shows a network error at launch every time. Fix in T13.

**D3. Every error collapses to one string.** Seven `catch` blocks in
`OwnerAppModel` assign the same `"Can't reach the server. Retrying."`, at lines
354, 398, 414, 442, 457, 481, and 525. Every one of them covers work that can
fail for reasons other than the network: creating a pairing code, rotating it,
revoking a viewer, publishing, and deleting.

The setup-time failures take a different path and are worth knowing about
separately. `loadRecoveryPhrase()`, `loadStoredPairingCode()`, and
`existingRegistration(from:)` all rethrow into `AppLaunchCoordinator`'s single
generic catch, which sets `.setupRequired` with one message and renders nowhere
(see D6 and W10). So a local storage failure and a bad recovery phrase are equally
invisible, just invisible somewhere else.

The copy deck's rule is that every failure names what to do next. Fix in T13 and
§12.4, and cover both paths.

**D4. `PairingWindow` is presented twice.** `createPairingCode()` builds a raw
`NSPanel` in `showPairingWindow()`, and there is also a declared
`Window(id: "pairing")` scene. Two independent instances of the same view can be
on screen with divergent state. The scene wins; delete the panel. Fix in T05.

**D5. `applyLoadedOverride` writes "Available override".** That string is in no
copy deck and appears nowhere else. Fix in §12.

**D6. Deleting everything leaves the runtime dead with no signal.**
`deleteEverything()` calls `runtime.deleteEverything()`, which calls `stop()`,
and the app then sits with a live menu bar icon and a scheduler that is not
running. It does set `connectionLine = "Meeting Pulse was reset."`, so the
signal is not quite zero, but that line lives in a menu the user has no reason
to reopen and every other surface keeps rendering as though the app still
works. The UI must enter an explicit terminal state. Fix in T25.

---

## 2. Scope: what moves, what stays, what is new

### 2.1 Feature placement matrix

Every existing capability, plus the ones that exist in the packages but have
never been exposed.

| Capability | Today | After | In menu bar? |
|---|---|---|---|
| Current state and reason | Menu text | Mast, always visible | Yes, header |
| Publish freshness | Menu text | Mast rail + Watch | Yes, header |
| Set busy, 7 presets + Custom | Menu submenu | Watch status group | Yes, 7-preset submenu |
| Set available, 7 presets + Custom | Menu submenu | Watch status group | Yes, 7-preset submenu |
| Clear override | Menu button | Watch status group | Yes |
| Calls are okay | Menu toggle | Mast toggle | Yes |
| Check and publish now | Menu button | Window toolbar | No |
| Accessibility permission | Onboarding window | Watch + onboarding | No |
| Google Meet detection | Nowhere | Watch | No |
| Slack huddle detection | Nowhere | Watch | No |
| Sync retry / superseded | Nowhere | Watch banner | No |
| Create viewer link | Menu button | Sharing | No |
| Viewer code and links | Panel | Sharing | No |
| QR code for the link | Nowhere | Sharing | No |
| Paired viewers list | Nowhere (`listViewers` unused) | Sharing | No |
| Rotate viewer link | Menu button | Sharing | No |
| Revoke viewer access | Menu button | Sharing | No |
| Display name | Settings window | This Mac | No |
| Launch at login | Settings window | This Mac | No |
| Recovery phrase | Recovery window | This Mac | No |
| Install location warning | Silent launch state | This Mac banner | No |
| Delete everything | Menu button | This Mac, danger zone | No |
| Privacy boundary | Onboarding paragraph | Privacy section | No |
| Diagnostics | Window, 3 rows | Folded into Watch | No |
| Open the window | Does not exist | New | Yes |
| Quit | Menu button | Menu bar | Yes |

### 2.2 In scope

- One new local Swift package, `Packages/MPUI`, holding every view and token.
- One new main window scene, `station`, replacing four of the five old windows.
- A rebuilt onboarding window, three steps.
- A rebuilt menu bar: six items plus two submenus.
- A rebuilt menu bar icon: shape-carried state, template rendered.
- The data wiring in §1.2 and the defect fixes in §1.3.
- A new `MPSupport/Strings.swift` and the matching additions to
  `docs/copy/deck.md`. The deck already claims this file exists; it does not.

### 2.3 Out of scope

Do not touch these. Changing them is a scope violation, not initiative.

- Detection logic, `AXSnapshot`, selectors, the latch, the scheduler's tuning.
- `StatusReducer`. The three-state reduction and the fail-closed rules stand.
- Any Supabase schema, RPC, or RLS policy.
- The viewer web surface, its copy, or its tokens.
- What the payload contains. No new field leaves the Mac.
- Turnstile, the recovery protocol, the pairing hash.

### 2.4 The one thing that must not regress

`PRODUCT.md`: *the viewer must never learn how the state was produced.* The new
UI shows the owner a great deal more than before, including which source is
active and whether an override is running. None of that changes
`StatusPayload`. Before you finish, diff `StatusPayload` against `main`; if it
gained a field, you have broken the product.

---

## 3. The direction contract

Copy this block verbatim into the header comment of
`Packages/MPUI/Sources/MPUI/Station/StationWindow.swift`. It is the reminder
that survives a long build.

```
//  MEETING PULSE, THE STATION. DIRECTION CONTRACT.
//
//  THESIS: The owner's app is a watch station, not a settings pane. It refuses
//  the macOS default where the thing you are configuring is invisible until you
//  click into a tab. The signal you are publishing is on screen at all times,
//  rendered exactly as she sees it, and every control writes to it visibly.
//
//  OWN-WORLD: The harbour signal station of DESIGN.md, inherited unchanged.
//  Painted marine enamel plates on a wet-slate ground, chalked rail beneath,
//  brass for focus. The plate keeps its saturated paint in both appearances;
//  only the ground and rail follow the system. Native macOS chrome everywhere
//  else: system controls, system font, system materials, no custom scrollbars.
//
//  STORY: He opens this maybe four times ever. He wants to know it is working,
//  send her the link, and close it. He leaves believing the Mac cannot see
//  anything it should not.
//
//  FIRST VIEWPORT: A 288pt left column. Top two thirds is the enamel plate: the
//  day-shape, the state word, the supporting line, exactly the viewer's board.
//  Under it, the calls-are-okay switch. Under that, four section rows. At the
//  very bottom, one chalk line of publish freshness. Right column is the
//  working area, a grouped Form. Primary action for a first run is "Create the
//  viewer link" in Sharing. Manual status actions live in the Watch detail.
//
//  FORM: Live mast and ledger. Candidate 6 of 7 grounded structures for this
//  task. Seed key 5f3f7af2.
//
//  FINISH: unreviewed and undocumented is unfinished; this build ends with the
//  finish review, the verdict, and DESIGN.md.
```

### 3.1 Why the mast is not navigation

The mast is the product. Meeting Pulse publishes one word. Putting that word
permanently on screen, in the same lettering and the same paint she sees, does
three things a settings tab cannot:

1. It answers the only question he ever has, before he clicks anything.
2. It teaches the fail-closed rule by demonstration. He sets himself available,
   and the plate still reads `Meeting status unavailable`, because that is the
   truth of what she sees. No paragraph explains this as well as watching it.
3. It bounds the privacy claim visually. Everything on the plate is everything
   that leaves the Mac. There is nothing else to show.

### 3.2 The two registers, and why they must not merge

This is the single most important implementation detail in this document.

`MPCore.State` has three cases: `available`, `busy`, `unavailable`. **The
viewer's board has four faces, and they do not line up.**
`viewer/src/lib/freshness.ts` computes them like this:

```ts
if (!reading) return 'generic';
if (!reading.status.paired) return 'unpaired';
if (reading.status.schemaVersion > SUPPORTED_SCHEMA_VERSION) return 'generic';
if (age > STALE_AFTER_SECONDS) return 'generic';
if (reading.status.state !== 'busy') return 'generic';
return reading.status.callOkay ? 'callOkay' : 'meeting';
```

Read that last line carefully. **`callOkay` is a face, not a modifier**, and it
only exists when the state is `busy`. And `available` has no face at all: it
collapses into `generic`, the same face as unavailable, stale, offline, and
unsupported schema.

So the mast renders **two registers, stacked, never merged**:

- **The plate** shows what she sees. Three owner-reachable faces:
  - `busy` and calls not okay → cone, storm plate, `In a meeting`
  - `busy` and calls okay → pennant, amber plate, `In Meeting, but it's fine to ring through`
  - everything else → bare mast, bare plate, `Meeting status unavailable`
- **The chalk line under the plate** shows what he needs, which the plate
  cannot say: `Busy for another 12 minutes`, `Watching automatically`,
  `Waiting for Accessibility permission`, `Can't reach the server. Retrying.`

The fourth viewer face, `unpaired`, is not owner-reachable. It describes a
viewer device that has not entered a code, which is a property of her phone, not
of his Mac. Do not model it.

Two failure modes to avoid, both of which produce an app that looks finished and
lies:

1. **Giving `available` a green plate.** `--plate-clear` (`#10614A`) exists in
   `tokens.css` and is referenced by no rule in `board.css`. It is dead paint.
   If you use it, the owner sees a confident green board while his wife's page
   reads `Meeting status unavailable`.
2. **Treating calls-are-okay as an accent on top of the busy face.** It replaces
   the face. Cone becomes pennant, storm becomes amber, and the headline changes
   completely. A brass flag stuck on a red plate is not what she sees.

---

## 4. Design system

Everything in this section lives in `Packages/MPUI/Sources/MPUI/Theme/`.
No view declares a raw colour, duration, radius, or spacing value. If a view
needs a number that is not here, add it here first.

### 4.1 Colour

Ported from `viewer/src/styles/tokens.css` so the two surfaces are the same
paint. Hex values are the source of truth; the `Color` initialisers below are
derived from them.

`Theme/MPColor.swift`:

**Every colour that changes with appearance is a colour set, and nothing
branches in code.** There is no `@Environment(\.colorScheme)` anywhere in
`MPUI`. Asset catalogue entries live in
`Packages/MPUI/Sources/MPUI/Resources/Media.xcassets` and are reached with
`Color("Name", bundle: .module)`.

```swift
import SwiftUI

public enum MPColor {
  // Enamel plates. Three faces, matching the viewer's board.
  public static let plateStorm    = Color("PlateStorm",    bundle: .module)
  public static let plateStormRim = Color("PlateStormRim", bundle: .module)
  public static let plateAmber    = Color("PlateAmber",    bundle: .module)
  public static let plateAmberRim = Color("PlateAmberRim", bundle: .module)
  public static let plateBare     = Color("PlateBare",     bundle: .module)
  public static let plateBareRim  = Color("PlateBareRim",  bundle: .module)

  // NOT DECLARED, deliberately: --plate-clear (#10614A). It is dead paint in
  // the viewer and there is no owner-side state that may use it. See 3.2.

  // Paint. Fixed: it is always read on a plate, which is always dark.
  public static let paintWhite = Color(hex: 0xF2EFE8)

  // Chalk and brass are read on the ground, so they follow the appearance.
  public static let chalk = Color("Chalk", bundle: .module)
  public static let brass = Color("Brass", bundle: .module)   // focus rings

  // Ground.
  public static let ground     = Color("Ground",     bundle: .module)
  public static let groundRail = Color("GroundRail", bundle: .module)
}
```

The full catalogue:

| Colour set | Any / dark | Light |
|---|---|---|
| `Ground` | `#0C1418` | `#E7E3DA` |
| `GroundRail` | `#070E11` | `#D6D1C6` |
| `PlateStorm` | `#8C2A22` | `#9A3128` |
| `PlateStormRim` | `#5C1C16` | `#66201A` |
| `PlateAmber` | `#7D4C13` | `#7D4C13` |
| `PlateAmberRim` | `#52320D` | `#52320D` |
| `PlateBare` | `#3A4247` | `#55585B` |
| `PlateBareRim` | `#262C2F` | `#383A3C` |
| `Chalk` | `#C8CDCB` | `#3A403E` |
| `Brass` | `#E8B23A` | `#937025` |

Everything outside the plate uses AppKit semantic colours: `.primary`,
`.secondary`, `Color(nsColor: .controlBackgroundColor)`,
`Color(nsColor: .separatorColor)`, `.accentColor`. Do not paint the window.

#### Measured contrast

Computed with the WCAG 2.2 relative-luminance formula, **in both appearances**,
and for supporting text at its actual composited opacity rather than at full
strength. Re-run all of it after any colour change; do not assume, and do not
measure dark mode only. The first draft of this plan did exactly that and
shipped five failing pairs.

Headlines, `paintWhite` at full opacity:

| Background | Dark | Light | Requirement |
|---|---|---|---|
| `plateStorm` | 7.41:1 | 6.43:1 | 4.5:1 |
| `plateAmber` | 6.27:1 | 6.27:1 | 4.5:1 |
| `plateBare` | 8.92:1 | 6.23:1 | 4.5:1 |

Supporting lines, `paintWhite.opacity(0.78)` composited onto the plate:

| Background | Dark | Light | Requirement |
|---|---|---|---|
| `plateStorm` | 5.13:1 | 4.52:1 | 4.5:1 |
| `plateAmber` | 4.52:1 | 4.52:1 | 4.5:1 |
| `plateBare` | 6.18:1 | 4.54:1 | 4.5:1 |

Off the plate:

| Pair | Dark | Light | Requirement |
|---|---|---|---|
| `chalk` on `groundRail` | 12.08:1 | 6.96:1 | 4.5:1 |
| `brass` on `ground` | 9.62:1 | 3.58:1 | 3:1 |

The margins on the supporting lines are thin, four of them within 0.05 of the
line. `0.78` is therefore a fixed constant, not a taste knob. Lowering it to
`0.75` fails. If a designer wants the supporting line quieter, make it smaller
or change the plate, and re-measure.

#### The plate colours above are not the viewer's, and that is deliberate

Four of the values in that catalogue diverge from `tokens.css`. Every divergence
is a WCAG AA failure in the shipping viewer, found while writing this plan and
verified by computing the ratios rather than by eye.

| Token | Viewer today | Measured | Here |
|---|---|---|---|
| `--plate-amber` (dark) | `#c97a1f` | 2.91:1 | `#7D4C13` |
| `--plate-amber` (light) | `#d98a2a` | 2.40:1 | `#7D4C13` |
| `--plate-bare` (light) | `#8a9094` | 2.81:1 | `#55585B` |
| `--plate-storm` (light) | `#a8352b` | 4.07:1 at 0.78 | `#9A3128` |

The amber pair is the worst of them, and it is the face carrying the product's
least obvious message: "he is busy, but ring anyway." If a reader cannot make
out that sentence, the feature is worse than absent.

Light-mode bare is the most common. `generic` is the face on screen whenever the
owner is not in a meeting, which is most of the day, and at 2.81:1 its headline
fails for anyone reading in a bright room.

Every replacement was derived the same way: hold the HSV hue and saturation,
walk the value down until the pair passes at the composited 0.78 opacity. They
are visibly the same paint, a shade deeper.

Two consequences for this build:

1. The Mac app ships the corrected values. Do not port a failing colour for the
   sake of a pixel match with a bug.
2. File a companion change to `viewer/src/styles/tokens.css` applying the same
   four values plus their rims. This is outside §2.3's scope boundary in spirit,
   but it is a handful of tokens and the two surfaces are supposed to be the
   same paint. Raise it as its own PR with the measurements attached; do not
   fold it into this one silently.

Write this up in `docs/decisions/` as part of T36. It is a defect found during
planning, not during implementation, and the reasoning should outlive this
document.

State is never carried by colour alone anywhere in this app. Every plate face
also has a distinct day-shape and a distinct word. Verify with a greyscale
screenshot before you call the build done.

### 4.2 Type

**One family: the system font.** `PRODUCT.md` sets Operate expectations for
this surface, and the viewer's own CSS falls through `'Archivo'` to
`-apple-system` because no `@font-face` is declared and `viewer/public/`
contains no font files. So SF Pro is not a compromise here; it is literally what
she sees on her phone. Do not bundle a webfont. See §17 for the follow-up.

Fixed point sizes, not fluid. Ratio ~1.2.

`Theme/MPFont.swift`:

```swift
public enum MPFont {
  // The plate. The only place with tightened tracking.
  public static let plateHeadline      = Font.system(size: 30, weight: .semibold)
  public static let plateHeadlineNamed = Font.system(size: 22, weight: .semibold)
  public static let plateName          = Font.system(size: 13, weight: .medium)
  public static let plateSupporting    = Font.system(size: 13, weight: .regular)

  // The station.
  public static let sectionTitle = Font.system(size: 20, weight: .semibold)
  public static let groupHeader  = Font.system(size: 13, weight: .semibold)
  public static let rowLabel     = Font.system(size: 13, weight: .regular)
  public static let rowValue     = Font.system(size: 13, weight: .regular)
  public static let caption      = Font.system(size: 11, weight: .regular)
  public static let chalkLine    = Font.system(size: 11, weight: .regular)

  // Codes and phrases.
  public static let code   = Font.system(size: 22, weight: .semibold, design: .monospaced)
  public static let phrase = Font.system(size: 15, weight: .regular, design: .monospaced)
}
```

Tracking: `plateHeadline` and `plateHeadlineNamed` get `.tracking(-0.9)` and
`.tracking(-0.66)` respectively (`-0.03em` at each size). Nothing else gets
tracking. The floor is `-0.04em`; do not go past it.

Prose blocks (the Privacy section, the recovery warning, onboarding body) are
capped at 66 characters with `.frame(maxWidth: 460)`. Data rows are not capped.

Every size above must survive Larger Text. Use `Font.system(size:weight:)`
which scales, never `.custom(_:fixedSize:)`.

### 4.3 Spacing

Base step 4pt, matching the viewer's `--step`.

```swift
public enum MPSpace {
  public static let hair: CGFloat  = 4
  public static let tight: CGFloat = 8
  public static let snug: CGFloat  = 12
  public static let base: CGFloat  = 16
  public static let wide: CGFloat  = 20
  public static let loose: CGFloat = 24
  public static let open: CGFloat  = 32
  public static let vast: CGFloat  = 40
}
```

Rules, applied everywhere:

- Inside a group of related rows: `tight` (8).
- Between groups: `loose` (24).
- Above a section heading: `open` (32). Below it: `snug` (12). More space above
  a heading than below it, always.
- Sidebar outer padding: `base` (16) horizontal, `wide` (20) top.
- Detail pane outer padding: `open` (32) horizontal, `loose` (24) vertical.

### 4.4 Shape and elevation

```swift
public enum MPRadius {
  public static let plate: CGFloat  = 14   // matches --radius-plate
  public static let well: CGFloat   = 10
  public static let cell: CGFloat   = 6    // pairing code characters
  public static let pill: CGFloat   = 999  // small controls only
}
```

**Declare elevation once.** The plate uses a shadow and no border. Wells use a
1px `separatorColor` border and no shadow. Never both.

Plate shadow, ported from the viewer's `0 28px 60px rgb(0 0 0 / 28%)` and
scaled for a 288pt plate:

```swift
.shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
```

Offset and blur are both non-zero. A zero-offset coloured halo is decoration and
is banned.

### 4.5 Motion tokens

`Theme/MPMotion.swift`. Every animation in the app resolves to one of these six.
A view that reaches for a raw `.easeInOut(duration:)` has broken the system.

```swift
public enum MPMotion {
  /// The signature. Ported from the viewer's --dur-hoist / --ease-hoist.
  /// cubic-bezier(0.16, 1, 0.3, 1), 220ms.
  public static let hoist = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)

  /// Physical arrival of a shape or a panel.
  public static let settle = Animation.spring(duration: 0.34, bounce: 0.22)

  /// Controls responding to the pointer. Never longer than this.
  public static let quick = Animation.easeOut(duration: 0.15)

  /// Text and value swaps.
  public static let chalk = Animation.easeInOut(duration: 0.18)

  /// Section content exchange.
  public static let leaf = Animation.easeOut(duration: 0.18)

  /// Rows landing in a list, per-item delay applied by the caller.
  public static let land = Animation.spring(duration: 0.28, bounce: 0.15)
}
```

Every duration sits in the 150-250ms band that Operate surfaces need, except
`settle` and `land`, which are springs whose perceptual settle is inside it.

**Reduced motion.** One helper, used at every call site. Nothing else.

```swift
public extension EnvironmentValues {
  /// Returns nil when Reduce Motion is on, so `withAnimation(nil)` and
  /// `.animation(nil, value:)` both become instant.
  func motion(_ animation: Animation?) -> Animation? {
    accessibilityReduceMotion ? nil : animation
  }
}
```

Reduced motion must still change the state instantly. It must never skip the
state change, and it must never leave a view mid-transition.

### 4.6 Iconography

**Drawn, one library, one weight.** SF Symbols throughout, `.regular` weight,
`.medium` for toolbar items. No emoji anywhere. No Unicode glyphs standing in
for icons.

The day-shapes are the exception and are authored SVG geometry ported to
SwiftUI `Shape` types, because they come from the world and no symbol matches
them. They are geometry, not illustration: exact coordinates, no shading, no
perspective.

`Theme/DayShape.swift`, ported from `viewer/src/pages/index.astro`:

```swift
/// viewBox 0 0 120 180, stroke width 5, round caps and joins.
/// One shape per plate face. shapeFor() in viewer/src/ui/board.ts is the source.
public enum DayShape: String, CaseIterable, Sendable {
  case cone     // busy, calls not okay
  case pennant  // busy, calls okay
  case mast     // everything else
}
```

Path data, copied from `viewer/src/pages/index.astro` lines 26-36. These are
exact; do not round, redraw, or improve them.

| Shape | Filled paths | Stroked paths |
|---|---|---|
| `cone` | `M60 18 28 74h64L60 18Z` | `M60 74v102M32 132h56` |
| `mast` | none | `M60 18v158M24 64h72M36 64v22M84 64v22` |
| `pennant` | `M60 30 100 50 60 70Z` | `M60 18v158` |

Note what the pennant actually is: a **bare pole with a flag**, with no yard and
no lifts. It is not the mast shape with something added. Getting this wrong is
the most likely way to break the mirror, because "pennant equals mast plus flag"
is the obvious guess and it is not what the viewer draws.

Fills are `paintWhite`. Strokes are `paintWhite`. Nothing in a day shape is
brass; brass is for focus and for attention markers only.

Render at 88 × 132 points inside the plate. Stroke width scales
proportionally: `5 * (88 / 120) = 3.67`, rounded to `3.7`.

Symbol assignments, fixed. Do not substitute. Menu bar symbols are in §9.3.

| Where | Symbol | Notes |
|---|---|---|
| Watch section | `eye` | Sidebar row |
| Sharing section | `link` | Sidebar row |
| This Mac section | `desktopcomputer` | Sidebar row |
| Privacy section | `hand.raised` | Sidebar row |
| Check and publish now | `arrow.clockwise` | Toolbar |
| Copy | `doc.on.doc` → `checkmark` | `.contentTransition(.symbolEffect(.replace))` |
| Google Meet source | `video` | Watch row |
| Slack huddle source | `waveform` | Watch row |
| Accessibility granted | `checkmark.seal` | Watch row |
| Accessibility missing | `exclamationmark.triangle` | Watch row |
| Publishing healthy | `antenna.radiowaves.left.and.right` | Watch row |
| Viewer paired | `person` | Sharing list row |
| Recovery phrase | `key` | This Mac row |
| Danger zone | `trash` | This Mac row |

### 4.7 Reusable components

Build these once in `Packages/MPUI/Sources/MPUI/Components/`. Every screen uses
them. Two screens that render the same idea differently is a defect.

| Component | File | Purpose |
|---|---|---|
| `MPRow` | `MPRow.swift` | Label, optional detail, trailing content, hover fill |
| `MPGroup` | `MPGroup.swift` | Header + rows in a bordered well |
| `MPStateChip` | `MPStateChip.swift` | Small shape + word, for source rows |
| `MPCopyButton` | `MPCopyButton.swift` | Copy with the checkmark swap, 1.6s revert |
| `MPBanner` | `MPBanner.swift` | Full-width notice: info, caution, alert |
| `MPEmptyState` | `MPEmptyState.swift` | Bare-mast glyph, one line, one action |
| `MPSkeleton` | `MPSkeleton.swift` | Loading sweep, ported from `.loading__*` |
| `MPDangerButton` | `MPDangerButton.swift` | Destructive with typed confirmation |
| `MPPlate` | `Mast/MPPlate.swift` | The enamel plate. See §6 |

**Every one of these ships seven states**: default, hover, focus, pressed,
disabled, loading, error. A component with three states is not done. Assert this
in review, not at the end.

**Every `public` view needs an explicit `public init`.** A memberwise
initialiser is internal even when the type is public, so
`MenuBarIcon(face:label:isDimmed:)` called from the app target will not compile
without one. This applies to `StationWindow`, `MenuBarContent`, `MenuBarIcon`,
`OnboardingWindow`, and every component above. The code samples in this document
omit the inits for brevity; do not read that as permission to omit them in the
implementation.

---

## 5. Package and scene architecture

### 5.1 Why a new package

`MeetingPulseApp.swift` is 1,112 lines because there is nowhere else to put
code. The Xcode project is hand-written with sequential placeholder UUIDs
(`A000000000000000000000NN`) and `objectVersion = 60`, so adding thirty files to
the app target means thirty `PBXFileReference` entries, thirty `PBXBuildFile`
entries, and thirty `PBXSourcesBuildPhase` lines, hand-edited, with UUID
collisions waiting.

The project already has a clean pattern for this: four `XCLocalSwiftPackageReference`
entries pointing at `Packages/MPCore`, `MPSupport`, `MPDetection`, `MPSync`.
Adding a fifth costs five pbxproj lines total and then any number of Swift files
with no further project edits.

So: **`Packages/MPUI`**. It also gets SwiftUI previews, compiles without the app
target, and makes the layering enforceable by the compiler.

### 5.2 Dependency direction

```
       MeetingPulseApp (target)
                |
                v
             MPUI  ──────────────┐
              |                  |
              v                  v
       MPCore, MPSupport     (protocols only:
                              PulseActions)
                |
   MPDetection, MPSync ───────> MPCore
```

`MPUI` depends on `MPCore` (for `State`, `ManualOverride`, `SourceObservation`,
`PairingCodeFormat`) and `MPSupport` (for `Strings`). **`MPUI` must not import
`MPSync` or `MPDetection`.** Views never touch a transport or a scheduler. They
talk to `PulseStore`, which holds plain values, and call `PulseActions`, a
protocol the app target implements over `OwnerRuntime`. See §11.

Add this to `Packages/MPUI/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MPUI",
  platforms: [.macOS(.v14)],
  products: [.library(name: "MPUI", targets: ["MPUI"])],
  dependencies: [
    .package(path: "../MPCore"),
    .package(path: "../MPSupport"),
  ],
  targets: [
    .target(
      name: "MPUI",
      dependencies: ["MPCore", "MPSupport"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "MPUITests", dependencies: ["MPUI"]),
  ]
)
```

Match `swift-tools-version` and the `platforms` line to the existing packages
before you commit; read `Packages/MPCore/Package.swift` first and copy its
declaration exactly, changing only the names.

### 5.3 File map

Create every one of these. The list is exhaustive; nothing else should appear
in the package.

```
Packages/MPUI/
  Package.swift
  Sources/MPUI/
    Theme/
      MPColor.swift          §4.1
      MPFont.swift           §4.2
      MPSpace.swift          §4.3
      MPRadius.swift         §4.4
      MPMotion.swift         §4.5
      DayShape.swift         §4.6
      Color+Hex.swift        hex initialiser, internal
    Store/
      PulseStore.swift       §11.1  @Observable, the single view state
      PulseActions.swift     §11.2  protocol the app target implements
      PulseSnapshot.swift    §11.3  value types the store publishes
      ReasonLineBuilder.swift §11.1 pure function, unit-testable
      PreviewStore.swift     §11.5  fixtures for previews and tests
    Mast/
      MastView.swift         §6.1
      MPPlate.swift          §6.2
      DayShapeView.swift     §6.3
      ModeControl.swift      §6.5
      CallsOkaySwitch.swift  §6.6
      PublishRail.swift      §6.7
    Station/
      StationWindow.swift    §5.5   the NavigationSplitView
      StationSidebar.swift   §5.6
      StationSection.swift   §5.6   the enum
      StationToolbar.swift   §5.7
      StationCommands.swift  §13.4  the ⌘1-⌘4 menu commands
    Sections/
      WatchSection.swift     §7.1
      SourceRow.swift        §7.1.3
      PermissionRow.swift    §7.1.2
      PublishingRow.swift    §7.1.4
      SharingSection.swift   §7.2
      ViewerLinkCard.swift   §7.2.2
      PairingCodeView.swift  §7.2.3
      QRCodeView.swift       §7.2.4
      PairedViewerRow.swift  §7.2.6
      ThisMacSection.swift   §7.3
      RecoveryPhraseView.swift §7.3.3
      DangerZone.swift       §7.3.5
      PrivacySection.swift   §7.4
    Onboarding/
      OnboardingWindow.swift §8
      OnboardingStep.swift   §8     the step enum and its content
      StepIndicator.swift    §8.5
    MenuBar/
      MenuBarContent.swift   §9
      MenuBarIcon.swift      §9.3
    Components/
      MPRow.swift            §4.7
      MPGroup.swift
      MPStateChip.swift
      MPCopyButton.swift
      MPBanner.swift
      MPEmptyState.swift
      MPSkeleton.swift
      MPDangerButton.swift
    Resources/
      Media.xcassets/        colour sets from §4.1
  Tests/MPUITests/
    PlateFaceTests.swift
    PlateFaceParityTests.swift
    ReasonLineTests.swift
    RelativeTimeTests.swift
    SourceStateTests.swift
    ContrastTests.swift
    StringsCoverageTests.swift
```

### 5.4 Scenes

`MeetingPulseApp.swift` shrinks to the scene declaration, the app delegate, the
runtime, and the `PulseActions` conformance. Everything else moves out.

Before:

```swift
MenuBarExtra { MenuBarView(...) } label: {
  HeartThreadMenuIcon(state: model.state)
    .task {                                    // the whole app starts here
      await launchCoordinator.start(model: model)
      appDelegate.terminationHandler = { await model.runtime?.gracefulQuit() }
    }
}
Window("Welcome to Meeting Pulse", id: "onboarding") { OnboardingWindow(...) }
Window("Pairing", id: "pairing")               { PairingWindow(...) }
Window("Meeting Pulse Settings", id: "settings")   { SettingsWindow(...) }
Window("Recovery", id: "recovery")             { RecoveryWindow(...) }
Window("Diagnostics", id: "diagnostics")       { DiagnosticsWindow(...) }
```

After:

```swift
var body: some Scene {
  MenuBarExtra {
    MenuBarContent(store: store, actions: self)
  } label: {
    MenuBarIcon(face: store.plateFace,
                label: store.plateHeadline,
                isDimmed: store.deleteCompleted)
      .task {
        await launchCoordinator.start(model: model)
        appDelegate.terminationHandler = { await model.runtime?.gracefulQuit() }
      }
  }
  .menuBarExtraStyle(.menu)

  Window(Strings.App.stationWindowTitle, id: StationWindow.sceneID) {
    StationWindow(store: store, actions: self)
  }
  .defaultSize(width: 940, height: 620)
  .defaultPosition(.center)
  .windowResizability(.contentMinSize)
  .commands { StationCommands(actions: self) }

  Window(Strings.App.setupWindowTitle, id: OnboardingWindow.sceneID) {
    OnboardingWindow(store: store, actions: self)
  }
  .defaultSize(width: 560, height: 480)
  .defaultPosition(.center)
  .windowResizability(.contentSize)
}
```

Keep the `.task`. It is not decoration on the icon: it is the only thing that
starts the app. `AppLaunchCoordinator.start` builds the runtime, loads the
local secret file, starts detection, and installs the termination handler, and it is
attached to the `MenuBarExtra` label because that is the one view guaranteed to
exist on every launch. The station window may never be opened. Dropping the
`.task` ships a binary that renders a menu and does nothing else, and the
failure is silent.

Deleted scenes: `pairing`, `settings`, `recovery`, `diagnostics`. Delete the
view types too; do not leave them orphaned. Also delete `showPairingWindow()`
and its raw `NSPanel` construction (defect D4).

`.defaultSize`, `.defaultPosition`, and `.windowResizability` are all macOS 13+.
`Window` is macOS 13+. All safe at the 14.0 deployment target.

**Do not** reach for `.containerBackground(.ultraThinMaterial, for: .window)`.
`ContainerBackgroundPlacement.window` is macOS 15. Neither `.windowLevel`,
`.restorationBehavior`, `.defaultLaunchBehavior`, `WindowStyle.plain`, nor
`UtilityWindow` are available. See §17.1 for the full gate list and the
`extension Scene` workaround if you decide you need one.

### 5.5 The window

`Station/StationWindow.swift`.

```
┌───────────────────────────┬───────────────────────────────────────────┐
│  288pt fixed              │  detail, min 572pt                        │
│                           │                                           │
│  ┌─────────────────────┐  │   Watch                          [↻]      │
│  │                     │  │                                           │
│  │        ▲            │  │   ┌─────────────────────────────────┐     │
│  │       ╱ ╲           │  │   │ Permission                      │     │
│  │      ╱___╲          │  │   │ ...                             │     │
│  │        │            │  │   └─────────────────────────────────┘     │
│  │     ───┼───         │  │                                           │
│  │        │            │  │   ┌─────────────────────────────────┐     │
│  │                     │  │   │ What the Mac watches            │     │
│  │   In a meeting      │  │   │ ...                             │     │
│  │   Better to wait.   │  │   └─────────────────────────────────┘     │
│  └─────────────────────┘  │                                           │
│                           │                                           │
│  Busy for another 12 min  │                                           │
│                           │                                           │
│  [ Busy │ Auto │ Free ]   │                                           │
│  Until  ⟨ 30 minutes ⟩    │                                           │
│  Calls are okay      (•)  │                                           │
│                           │                                           │
│  ─────────────────────    │                                           │
│  👁  Watch                │                                           │
│  🔗  Sharing              │                                           │
│  🖥  This Mac             │                                           │
│  ✋  Privacy              │                                           │
│                           │                                           │
│  ─────────────────────    │                                           │
│  Published 12 seconds ago │                                           │
└───────────────────────────┴───────────────────────────────────────────┘
```

```swift
public struct StationWindow: View {
  public static let sceneID = "station"

  @Bindable var store: PulseStore
  let actions: any PulseActions
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public var body: some View {
    NavigationSplitView {
      StationSidebar(store: store, actions: actions, section: $store.section)
        .navigationSplitViewColumnWidth(288)
    } detail: {
      detail
        .frame(minWidth: 572, maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .toolbar { StationToolbar(store: store, actions: actions) }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 860, minHeight: 560)
    .navigationTitle(store.section.title)
  }

  @ViewBuilder private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MPSpace.loose) {
        switch store.section {
        case .watch:   WatchSection(store: store, actions: actions)
        case .sharing: SharingSection(store: store, actions: actions)
        case .thisMac: ThisMacSection(store: store, actions: actions)
        case .privacy: PrivacySection()
        }
      }
      .padding(.horizontal, MPSpace.open)
      .padding(.vertical, MPSpace.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .id(store.section)
    .transition(.opacity)
    .animation(reduceMotion ? nil : MPMotion.leaf, value: store.section)
  }
}
```

Sidebar width is fixed at 288, not a range. The mast is an instrument with a
drawn plate at a specific size; letting the user drag it to 180pt breaks the
composition and gains nothing. Use the single-value
`.navigationSplitViewColumnWidth(288)` overload, not `min:ideal:max:`.

### 5.6 The sidebar and the section enum

`Station/StationSection.swift`:

```swift
public enum StationSection: String, CaseIterable, Identifiable, Sendable {
  case watch, sharing, thisMac, privacy
  public var id: String { rawValue }

  var title: String {
    switch self {
    case .watch:   Strings.Station.watchTitle
    case .sharing: Strings.Station.sharingTitle
    case .thisMac: Strings.Station.thisMacTitle
    case .privacy: Strings.Station.privacyTitle
    }
  }

  var symbol: String {
    switch self {
    case .watch:   "eye"
    case .sharing: "link"
    case .thisMac: "desktopcomputer"
    case .privacy: "hand.raised"
    }
  }
}
```

`Station/StationSidebar.swift` layout, top to bottom:

1. `MastView` (§6). Padding: 16 horizontal, 20 top.
2. `Spacer(minLength: MPSpace.loose)`.
3. `Divider()`.
4. The section `List`, `.listStyle(.sidebar)`, `selection: $section` (bound
   through from `$store.section`). Each row is
   `Label(section.title, systemImage: section.symbol)`.

   Selection lives on `PulseStore`, not in a `@State` on `StationWindow`. Two
   things outside the view hierarchy set it: `StationCommands` (`⌘1`-`⌘4`, §13.4)
   and `PulseActions.openStation(section:)`, which the menu bar calls to open
   the window straight onto Sharing. Neither can reach a private `@State`.
5. `Spacer()`.
6. `Divider()`.
7. `PublishRail` (§6.7). Padding: 16 horizontal, 12 vertical.

The whole column is `.background(MPColor.ground)`. This is the one place the
app paints its own background, and it is justified: the mast is a picture of the
harbour and needs the wet-slate ground under it. The detail pane keeps the
system window background.

Attach a badge to the Watch row when attention is needed:

```swift
.badge(store.needsAttention ? 1 : 0)
```

`store.needsAttention` is true when Accessibility is missing, the install
location is wrong, or sync has been retrying for more than 30 seconds.

### 5.7 The toolbar

One item only. Resist adding more.

```swift
struct StationToolbar: ToolbarContent {
  let store: PulseStore
  let actions: any PulseActions

  var body: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        Task { await actions.checkAndPublishNow() }
      } label: {
        Label(Strings.Station.checkNow, systemImage: "arrow.clockwise")
      }
      .help(Strings.Station.checkNowHelp)
      .disabled(store.isPublishing)
      .keyboardShortcut("r", modifiers: .command)
    }
  }
}
```

The spin animation on this icon is specified in §10, item M16.

### 5.8 Opening and focusing the window

The app runs `.accessory` (`NSApplication.shared.setActivationPolicy(.accessory)`
in `init()`, and `LSUIElement` once §14.2 is applied). An accessory app's
windows do not come forward
on `openWindow(id:)` alone; the app has to activate itself first.

Put this in the app target, and route every window-opening path through it:

```swift
@MainActor func openStation(_ openWindow: OpenWindowAction) {
  NSApp.activate()                      // macOS 14+, no argument form
  openWindow(id: StationWindow.sceneID)
}
```

`NSApplication.activate()` without arguments is macOS 14+ and is the correct
call. Do not use `activate(ignoringOtherApps:)`; it is soft-deprecated with a
compiler message and formally deprecated in a later release.

`openWindow(id:)` on an already-open window brings it to the front rather than
opening a second one, so no bookkeeping is needed.

---

## 6. The mast

`Packages/MPUI/Sources/MPUI/Mast/`. This is the piece that makes the direction
real. Build it first, get it right, then build the sections around it.

### 6.1 Structure

`MastView.swift`, top to bottom, spacing `MPSpace.base` (16) between blocks:

| # | Element | Detail |
|---|---|---|
| 1 | `MPPlate` | 256 × 232, three faces. §6.2 |
| 2 | Reason chalk line | 11pt `chalk`, centred, 2 lines max. §6.4 |
| 3 | `ModeControl` | Three segments, full width. §6.5 |
| 4 | Duration row | Only when mode is Busy or Free. §6.5.2 |
| 5 | `CallsOkaySwitch` | Label + `Toggle(.switch)`. §6.6 |

### 6.2 The plate

`MPPlate.swift`. This is a picture of the viewer's board, at owner scale.

```
     256pt wide
┌────────────────────────┐  ─┐
│                        │   │
│                        │   │  24pt top padding
│         ▲              │   │
│        ╱ ╲             │   │  DayShapeView, 88 × 132
│       ╱___╲            │   │
│         │              │   │
│      ───┼───           │   │
│         │              │   │
│                        │   │  20pt gap
│    In a meeting        │   │  plateHeadline, paintWhite
│                        │   │  8pt gap
│    Better to wait.     │   │  plateSupporting, paintWhite @ 0.78
│                        │   │
│                        │   │  24pt bottom padding
└────────────────────────┘  ─┘
   232pt tall, at one headline line
```

232 is a minimum, not a fixed height, and the code below uses `minHeight` for
that reason. The paddings add up to 208 before either text is laid out, so a
single headline line already brings it to roughly 244, and the named `callOkay`
variant (`Mohit is in Meeting, but it's fine to ring through`) wraps to three
lines at this width. Pinning the height would clip it.

The plate growing is fine. It sits at the top of a 288pt column with a `Spacer`
under it, so nothing below shifts in a way the eye tracks, and the growth is
animated by the same `hoist` curve as the face change.

```swift
struct MPPlate: View {
  let face: PlateFace          // .meeting, .callOkay, or .generic
  let ownerName: String?
  let isOnline: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      DayShapeView(shape: face.dayShape, tint: MPColor.paintWhite)
        .frame(width: 88, height: 132)
        .padding(.top, MPSpace.loose)

      Spacer(minLength: MPSpace.wide)

      Text(headline)
        .font(ownerName == nil ? MPFont.plateHeadline : MPFont.plateHeadlineNamed)
        .tracking(ownerName == nil ? -0.9 : -0.66)
        .foregroundStyle(MPColor.paintWhite)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)

      Text(face.supporting(isOnline: isOnline))
        .font(MPFont.plateSupporting)
        .foregroundStyle(MPColor.paintWhite.opacity(0.78))
        .padding(.top, MPSpace.tight)
        .padding(.bottom, MPSpace.loose)
    }
    .frame(width: 256, minHeight: 232, alignment: .top)
    .background(
      RoundedRectangle(cornerRadius: MPRadius.plate, style: .continuous)
        .fill(face.plate)
        .overlay(
          RoundedRectangle(cornerRadius: MPRadius.plate, style: .continuous)
            .strokeBorder(face.rim, lineWidth: 2)
        )
    )
    .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    .animation(reduceMotion ? nil : MPMotion.hoist, value: face)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(headline)
    .accessibilityValue(face.supporting(isOnline: isOnline))
  }
}
```

`PlateFace` has exactly three cases and one initialiser. That initialiser is a
direct port of `effectiveDisplayState` in `viewer/src/lib/freshness.ts`, and it
is the only place in the Mac app allowed to decide what she sees.

```swift
public enum PlateFace: Equatable, Sendable {
  case meeting     // busy, calls not okay
  case callOkay    // busy, calls okay
  case generic     // available, unavailable, stale, offline, unsupported

  /// Port of freshness.ts effectiveDisplayState. Do not add cases.
  /// The viewer's fourth face, `unpaired`, is not owner-reachable. See 3.2.
  public init(state: State, callsOkay: Bool, isFresh: Bool) {
    guard isFresh, state == .busy else { self = .generic; return }
    self = callsOkay ? .callOkay : .meeting
  }

  var dayShape: DayShape {
    switch self {
    case .meeting:  .cone
    case .callOkay: .pennant
    case .generic:  .mast
    }
  }

  var plate: Color {
    switch self {
    case .meeting:  MPColor.plateStorm
    case .callOkay: MPColor.plateAmber
    case .generic:  MPColor.plateBare
    }
  }

  var rim: Color {
    switch self {
    case .meeting:  MPColor.plateStormRim
    case .callOkay: MPColor.plateAmberRim
    case .generic:  MPColor.plateBareRim
    }
  }

  func supporting(isOnline: Bool) -> String {
    switch self {
    case .meeting:  Strings.Board.meetingSupporting   // "Better to wait."
    case .callOkay: Strings.Board.callOkaySupporting  // "He said to go ahead and interrupt."
    case .generic:
      isOnline
        ? Strings.Board.genericSupporting             // "Check again before you call."
        : Strings.Board.genericOfflineSupporting      // "Connect to the internet, then check again."
    }
  }
}
```

The offline variant completes the mirror. `COPY.board.generic` in the viewer has
both a `supporting` and an `offlineSupporting`, and the board swaps to the
second when the browser reports no connection. `PulseStore.isOnline` (W7) is the
owner-side equivalent, so pass it in rather than letting the two surfaces say
different things about the same condition.

Headline, ported from `COPY.board` in `viewer/src/lib/copy.ts`. Note the
asymmetry: `meeting` and `callOkay` each have a with-name variant, and
**`generic` does not**. The viewer renders the bare generic headline whether a
name is set or not, and shows the name in a separate element beneath. Match it.

```swift
private var headline: String {
  switch (face, ownerName) {
  case (.meeting,  .some(let n)): Strings.Board.meetingNamed(n)   // "{Name} is in a meeting"
  case (.meeting,  .none):        Strings.Board.meeting           // "In a meeting"
  case (.callOkay, .some(let n)): Strings.Board.callOkayNamed(n)  // "{Name} is in Meeting, but it's fine to ring through"
  case (.callOkay, .none):        Strings.Board.callOkay          // "In Meeting, but it's fine to ring through"
  case (.generic, _):             Strings.Board.generic           // "Meeting status unavailable"
  }
}
```

The `callOkay` headlines are long. At 256pt the named variant wraps to three
lines, which is why `plateHeadlineNamed` drops to 22pt and the plate is 232pt
tall rather than the 200pt the busy face alone would need. Do not shrink the
plate to fit the shortest headline.

Do not write any of these strings inline. Re-read `viewer/src/lib/copy.ts`
before you ship. If the wording there has drifted from this table, the viewer is
right and this document is stale.

### 6.3 Day shapes

`DayShapeView.swift`. Ported from the authored SVG in
`viewer/src/pages/index.astro`. viewBox is `0 0 120 180`; scale to the frame.

`DayShapeView(shape:tint:)` is specified once, in §10.3, together with its
transition. Do not write a second version here.

`ConeShape`, `PennantShape`, and `MastShape` are **views, not `Shape`s**. Cone
and pennant each need a filled path and a stroked path, and a single `Shape`
returns one `Path` that is either filled or stroked, never both. Each is a small
view composing two `Path`-backed shapes in a `ZStack`, taking `tint` and
applying it to both. The mast has only a stroked path but follows the same
pattern so the three are interchangeable.

Or, preferred for animatability, build three `Shape` conformances and compose
them with `ZStack`. `Canvas` cannot be transitioned; `Shape` can. Use `Shape`.

Path data, exact:

```
cone, filled:   M60 18 28 74h64L60 18Z
cone, stroked:  M60 74v102  M32 132h56
mast, stroked:  M60 18v158  M24 64h72  M36 64v22  M84 64v22
pennant, stroked: M60 18v158
pennant, filled:  M60 30 100 50 60 70Z
```

Stroke: `lineWidth: 3.7` at an 88pt render width (`5 × 88/120`), `lineCap:
.round`, `lineJoin: .round`, colour `paintWhite`. Fills are `paintWhite` too.
Nothing in a day shape is brass, and nothing is tinted per face. The viewer sets
`fill: var(--pennant)` and `--pennant` is `#f2efe8`, which is `paintWhite`, so
the pennant flag is the same paint as the cone body. A brass pennant would also
break §9.3, whose template-image argument depends on every shape being one
colour.

The cone-to-mast transition is the app's signature moment. See §10, item M02.

### 6.4 The reason line

Directly under the plate. This is the second register: what he needs to know,
which the plate deliberately cannot say.

Derived from `store.reasonLine`, which the store computes with this precedence.
The order matters; the first match wins.

| # | Condition | Line | Tone |
|---|---|---|---|
| 1 | `deleteCompleted` | `Everything on this Mac is gone. Quit to finish.` | Alert |
| 2 | `!accessibilityGranted` | `Waiting for Accessibility permission` | Caution |
| 3 | `syncState == .superseded` | `Another Mac took over. This one has stopped.` | Alert |
| 4 | `syncState == .retrying` | `Can't reach the server. Retrying.` | Caution |
| 5 | `!hasViewerLink` | `No one is watching yet. Create a link.` | Info |
| 6 | override busy, timed | `Busy for another {n} minutes` | Info |
| 7 | override busy, untilCleared | `Busy until you clear it` | Info |
| 8 | override free, timed | `Available for another {n} minutes` | Info |
| 9 | override free, untilCleared | `Available until you clear it` | Info |
| 10 | `reason == .confirmedActiveSource` | `{Source} call detected` | Info |
| 11 | `reason == .untrustedSource` | `A window looked like a call. Not sure enough.` | Info |
| 12 | otherwise | `Watching automatically` | Info |
| 12a | any of 5-12 above, and `callsOkay` is on, and the face is `generic` | append `Calls are okay when you are busy.` | same |

Rendered `MPFont.chalkLine` in `MPColor.chalk`, centred, `lineLimit(2)`,
`.frame(maxWidth: 256)`. Caution and Alert tones prepend a 10pt
`exclamationmark.triangle.fill` in `MPColor.brass`, inline via a `Label`.

Row 6's minute count updates every second while an override runs. Use
`.contentTransition(.numericText(countsDown: true))` (macOS 13+) so the digits
roll rather than blink. See §10, item M04.

### 6.5 The mode control

`ModeControl.swift`. Three segments. This is the primary control of the whole
app.

```swift
Picker("", selection: $mode) {
  Text(Strings.Mast.modeBusy).tag(PulseMode.busy)
  Text(Strings.Mast.modeAuto).tag(PulseMode.automatic)
  Text(Strings.Mast.modeFree).tag(PulseMode.free)
}
.pickerStyle(.segmented)
.labelsHidden()
.frame(width: 256)
```

```swift
public enum PulseMode: Hashable, Sendable { case busy, automatic, free }
```

Mapping to the existing model, which does not change:

| Segment | Action | `ManualOverride` |
|---|---|---|
| Busy | `actions.setOverride(.busy, duration)` | `.init(state: .busy, ...)` |
| Automatic | `actions.clearOverride()` | `nil` |
| Free | `actions.setOverride(.available, duration)` | `.init(state: .available, ...)` |

`Automatic` sits in the middle deliberately. It is the resting state, the
segment he returns to, and centring it makes both overrides feel like temporary
departures in opposite directions.

#### 6.5.2 The duration row

Appears only when mode is `.busy` or `.free`. It slides down from beneath the
picker rather than appearing, so the layout reads as one control growing.

```swift
if mode != .automatic {
  HStack {
    Text(Strings.Mast.durationLabel)          // "Until"
      .font(MPFont.rowLabel)
      .foregroundStyle(MPColor.chalk)
    Spacer()
    Picker("", selection: $duration) {
      ForEach(ManualOverride.Duration.allCases) { d in
        Text(d.displayName).tag(d)
      }
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .fixedSize()
  }
  .frame(width: 256)
  .transition(.asymmetric(
    insertion: .push(from: .top).combined(with: .opacity),
    removal:   .opacity
  ))
}
```

The seven durations come from `MPCore.ManualOverride.Duration` and their labels
from the copy deck: `15 minutes`, `30 minutes`, `45 minutes`, `1 hour`,
`2 hours`, `4 hours`, `Until I clear it`. Add `displayName` as an extension in
`MPUI`, sourced from `Strings.Duration`, not as raw literals in the picker.

`ManualOverride.Duration` is declared `CaseIterable, Equatable, Sendable` and
nothing more, so `ForEach(ManualOverride.Duration.allCases)` and `.tag(d)` both
fail to compile as written. Add the two missing conformances in the same MPUI
extension:

```swift
extension ManualOverride.Duration: Identifiable, Hashable {
  public var id: Self { self }
  public var displayName: String { ... }   // from Strings.Duration
}
```

Retroactive conformance on a type from another module warns under Swift 6. If
the warning is treated as an error in this project, add `Hashable` and
`Identifiable` to the declaration in `MPCore` instead. Either is fine; leaving
it as it stands is not.

Default duration is `.m30`. Persist the last chosen value in
`PulseStore.preferredDuration` so a second override does not make him choose
again.

### 6.6 Calls are okay

`CallsOkaySwitch.swift`.

```swift
HStack {
  Text(Strings.Mast.callsOkayLabel)          // "Calls are okay"
    .font(MPFont.rowLabel)
    .foregroundStyle(MPColor.paintWhite)
  Spacer()
  Toggle("", isOn: $callsOkay)
    .toggleStyle(.switch)
    .labelsHidden()
}
.frame(width: 256)
```

**This toggle repaints the plate when he is busy, and does nothing visible when
he is not.** That is not a bug to paper over; it is the truth, and the mast is
the one place he can learn it without reading anything.

- Busy, toggled on: the plate hoists from cone to pennant, storm to amber, and
  the headline changes to `In Meeting, but it's fine to ring through`. A full
  face change, animated by M01 and M02 like any other.
- Not busy, toggled on: the plate does not move, because `effectiveDisplayState`
  never reaches the `callOkay` branch unless the state is `busy`. The reason
  line is what acknowledges the click.

So when the toggle is on and the face is `generic`, the reason line gains a
suffix: `Watching automatically. Calls are okay when you are busy.` This is
row 12a in §6.4's table. Without it the toggle looks broken.

Do not model calls-are-okay as an accent, a badge, or a flag added to another
shape. `PlateFace` already encodes it, and `DayShapeView` takes a single shape.
If you find yourself adding a second, overlaid shape, re-read §3.2.

### 6.7 The publish rail

`PublishRail.swift`, pinned to the bottom of the sidebar. One line of chalk on
the darker `groundRail` background, the way a real station chalks its last
signal on the board below the mast.

Content, by `store.publishState`:

| State | Line |
|---|---|
| `.never` | `Nothing published yet` |
| `.published(at:)` | `Published {relative} ago` |
| `.publishing` | `Publishing...` |
| `.retrying` | `Can't reach the server. Retrying.` |
| `.offline` | `No network. Waiting.` |
| `.superseded` | `Another Mac is publishing now` |

`.offline` outranks `.retrying`. When `store.isOnline` is false, show the
offline line even if a request is also failing, because "no network" is
something he can act on and "retrying" is not.

The relative time uses a coarse formatter, never seconds-precise past a minute:
`just now` under 10s, `{n} seconds ago` under 60s, `{n} minutes ago` under 60m,
`{n} hours ago` beyond. Ticks on a 1-second `Timer` while the window is visible
and stops when it is not. Do not run a timer behind a closed window.

`.retrying` and `.superseded` render the text in `MPColor.brass`.

---

## 7. Section specs

Every section is a `VStack(alignment: .leading, spacing: MPSpace.loose)` of
`MPGroup`s. Every group has a header in `MPFont.groupHeader` and rows built from
`MPRow`. Two sections that render the same idea differently is a defect.

### 7.1 Watch

Answers "is this actually working?". Absorbs the old Diagnostics window.

```
Watch

  Permission
  ┌──────────────────────────────────────────────────────┐
  │ ✓  Accessibility                        Granted      │
  │    Meeting Pulse reads window titles.                │
  └──────────────────────────────────────────────────────┘

  What the Mac watches
  ┌──────────────────────────────────────────────────────┐
  │ 🎥 Google Meet             In a call    ●            │
  │    Checked 3 seconds ago                             │
  ├──────────────────────────────────────────────────────┤
  │ 〰 Slack huddles           No call                    │
  │    Checked 3 seconds ago                             │
  └──────────────────────────────────────────────────────┘

  Publishing
  ┌──────────────────────────────────────────────────────┐
  │ Last published            12 seconds ago             │
  │ Checks run           Every 5s in a call, 20s idle    │
  │ This Mac                  Publishing                 │
  └──────────────────────────────────────────────────────┘
```

#### 7.1.1 The attention banner

When `!store.accessibilityGranted`, an `MPBanner(.caution)` sits above
everything with the headline `Meeting Pulse can't see your windows yet.`, the
body `Turn on Accessibility so the Mac can read window titles. It never reads
what is inside them.`, and a button `Open Accessibility settings`.

The button opens:

```swift
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
```

This URL scheme is undocumented. Guard it: if `NSWorkspace.shared.open(_:)`
returns `false`, fall back to a second banner line reading `Open System
Settings, then Privacy & Security, then Accessibility.` Do not let a failed
`open` be silent.

When `store.syncState == .superseded`, an `MPBanner(.alert)` replaces it:
headline `Another Mac took over.`, body `Meeting Pulse is running somewhere
else. This Mac has stopped publishing.`, no button.

#### 7.1.2 Permission row

`PermissionRow.swift`. `MPRow` with a leading symbol, a label, and a trailing
value.

| Granted | Symbol | Tint | Value |
|---|---|---|---|
| Yes | `checkmark.seal` | `.secondary` | `Granted` |
| No | `exclamationmark.triangle` | `MPColor.brass` | `Not granted` |

Subtitle, always: `Meeting Pulse reads window titles. It never reads what is
inside them.`

Bind to a live `PermissionCoordinator.changes` stream, not a value read at
launch (§11.4). The row must flip without a relaunch.

`PermissionCoordinator(pollInterval:)` defaults to 5 seconds, which is too slow
for a screen the user is staring at having just returned from System Settings.
Construct it with `.seconds(1)` while onboarding is on screen or the Watch
section is frontmost, and leave the default everywhere else. Do not change the
default in `MPSupport`; a 1-second poll running forever is a battery cost for a
value that almost never changes. This is the single most
common first-run failure in accessibility-gated Mac apps and the reason the
stream exists.

#### 7.1.3 Source rows

`SourceRow.swift`. One per `SourceID`. Driven by `SchedulerReading`, which is
currently discarded (§1.2).

```swift
struct SourceRow: View {
  let source: SourceID              // .googleMeet, .slackHuddle
  let observation: SourceObservation?
  let seenAt: Date?
}
```

| Column | Content |
|---|---|
| Leading symbol | `video` for Meet, `waveform` for Slack |
| Label | `Google Meet` / `Slack huddles` |
| Value | `In a call` / `No call` / `Can't tell` |
| Chip | `MPStateChip`, filled dot only when `In a call` |
| Subtitle | `Checked {relative} ago`, from `seenAt` |

Map `SourceObservation` directly: `.active` is `In a call`, `.inactive` is `No
call`, and both `.unknown` and `.sourceAbsent` are `Can't tell`. It never
renders as `No call`. `PRODUCT.md`'s fail-closed rule is explicit that
`unknown` must not be mapped to `inactive`, and the UI has to honour it as
literally as the reducer does.

Do not take a `DetectorHealth`. The enum exists in `MPCore`, but its cases are
`ok`, `degraded(DiagnosticCode)`, `permissionDenied`, and `absent`, with no
`unknown`, and more to the point `SchedulerReading` does not carry it. The
reading has three fields: `meet`, `slack`, `accessibilityGranted`. Health never
leaves the detector, so the UI cannot show it without an MPDetection change,
which §2.3 puts out of scope. `SourceObservation` already distinguishes the case
that matters to him, which is "we could not tell", and `.sourceAbsent` covers a
missing app.

`seenAt` is the timestamp the store records when it receives a reading, not a
value from the scheduler. Set both `meetSeenAt` and `slackSeenAt` to `.now` in
W1 each time a `SchedulerReading` arrives.

Empty state, when a source has never reported: the row still renders, value
`Not seen yet`, subtitle `Meeting Pulse will notice the next time you join.`
Do not hide the row. A missing row reads as a bug.

#### 7.1.4 Publishing rows

`PublishingRow.swift`. Three `LabeledContent` rows.

| Label | Value | Source |
|---|---|---|
| `Last published` | relative time | `SyncCoordinator.lastSuccessfulSync` |
| `Checks run` | `Every {active}s in a call, {idle}s idle` | `DetectionTuning`, formatted |
| `This Mac` | `Publishing` / `Retrying` / `Stopped` | `SyncCoordinator.currentState` |

`Checks run` is a formatted value, not a literal, and there are two numbers
rather than one. `DetectionTuning` has `activeSampleInterval` (default 5
seconds) and `idleSampleInterval` (default 20 seconds), and the scheduler picks
between them depending on whether anything is currently active. Earlier drafts
of this plan said "Every 4 seconds", which is a number that appears nowhere in
the code.

`DetectionScheduler` exposes `updateTuning` but no getter, so the store cannot
read the values back out. Hold the tuning where it is constructed, in
`OwnerRuntime`, and push both intervals into `idleCheckInterval` and
`activeCheckInterval` at the same moment you hand them to the scheduler. That
keeps one construction site and no drift.

### 7.2 Sharing

The most important screen on first run, and the one he will return to when
someone new needs the link.

#### 7.2.1 Empty state

Before a viewer link exists, the section is a single centred `MPEmptyState`:

- Glyph: `DayShapeView(shape: .mast, tint: MPColor.chalk)` at 64 × 96, 40% opacity.
- Headline: `No one is watching yet.`
- Body: `Create a link and send it to whoever needs to know when to call.`
- Button: `Create the viewer link`, `.borderedProminent`, `.controlSize(.large)`.

This is the primary action of the whole app on first run. It is the only
prominent-styled button in the window; nothing else competes with it.

#### 7.2.2 The viewer link card

Once a link exists, `ViewerLinkCard.swift` renders:

```
  The link
  ┌──────────────────────────────────────────────────────┐
  │                                                      │
  │   ┌────┐┌────┐┌────┐┌────┐┌────┐                     │
  │   │ K  ││ 4  ││ M  ││ 2  ││ P  │  ─                  │
  │   └────┘└────┘└────┘└────┘└────┘                     │
  │   ┌────┐┌────┐┌────┐┌────┐┌────┐    ┌───────────┐    │
  │   │ 9  ││ R  ││ T  ││ 7  ││ B  │    │ ▓▓ ▓  ▓▓▓ │    │
  │   └────┘└────┘└────┘└────┘└────┘    │ ▓  ▓▓ ▓ ▓ │    │
  │                                     │ ▓▓ ▓  ▓▓▓ │    │
  │   meetingpulse.app/#code=K4M2P9RT7B  └───────────┘   │
  │                                                      │
  │   [Copy link]  [Copy code]  [Share]                  │
  │                                                      │
  └──────────────────────────────────────────────────────┘
```

Two things about that URL. The code travels in the **fragment**, not the path:
`PairingService.link` sets `components.fragment = "code=\(normalized)"`, which
is what keeps the code out of server logs and referrer headers. And the code in
the link is normalised to uppercase, while the display grouping adds the dash.
Render the real URL; do not invent a prettier one.

There may also be more than one. `AppConfiguration.viewerOrigins` is an array
and `OwnerRuntime.pairingLinks(for:)` returns `[URL]`, one per origin, which is
why `PulseStore` holds `viewerLinks: [URL]` rather than a single value. With one
origin, render exactly what is drawn above. With more than one, keep the single
card and turn `Copy link` into a `Menu` with one item per host, labelled
`Copy {host} link`. Do not render a second card, and do not silently drop the
extra origins the way an earlier draft of this plan did.

#### 7.2.3 The pairing code

`PairingCodeView.swift`. Ten characters in two rows of five, with no separator
in the displayed value. Each character is its own 28 × 34 cell:

```swift
RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous)
  .fill(Color(nsColor: .controlBackgroundColor))
  .overlay(
    RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous)
      .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
  )
  .overlay(Text(String(character)).font(MPFont.code))
  .frame(width: 28, height: 34)
```

`.fill(_:)` returns a view, not a shape, so `.stroke` cannot be chained onto it.
Use `.overlay` with a second copy of the shape, and prefer `strokeBorder` over
`stroke` so the line sits inside the bounds instead of straddling them. The same
pattern applies to the plate in §6.2 and anywhere else a filled shape needs a
rim.

Cells exist so he can read the code aloud over a phone without losing his place.
That is the whole reason; do not decorate them further. `.textSelection(.enabled)`
on the whole group so he can also select it.

The landing animation is §10, item M09.

#### 7.2.4 QR code

`QRCodeView.swift`. Generated locally with CoreImage. No network call, no third
party. 120 × 120, rendered `paintWhite` on `.clear` so it inverts correctly in
both appearances.

```swift
import CoreImage.CIFilterBuiltins

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(link.utf8)
filter.correctionLevel = "M"
```

Scale the output with `CGAffineTransform(scaleX: 8, y: 8)` before rasterising so
it is not blurry, and set `.interpolation(.none)` on the `Image`.

Clicking the QR opens a 360 × 360 popover of the same code, for holding the Mac
up to a phone. `.presentationCompactAdaptation` is not needed on macOS.

#### 7.2.5 Actions

| Button | Style | Behaviour |
|---|---|---|
| `Copy link` | `.bordered` | `MPCopyButton`, copies the full URL |
| `Copy code` | `.bordered` | `MPCopyButton`, copies `ABCDEFGHJK` |
| `Share` | `.bordered` | `ShareLink(item: url)`, macOS 13+ |
| `Create a new link` | `.link` | Confirmation required. Rotates |
| `Stop sharing` | `.link`, `.red` | Confirmation required. Revokes |

Rotate confirmation, `.confirmationDialog`: title `Create a new link?`, message
`The old link stops working right away. Anyone using it will need the new one.`,
buttons `Create a new link` (destructive) and `Cancel`.

Revoke confirmation: title `Stop sharing?`, message `The link stops working
right away. No one will be able to see your status.`, buttons `Stop sharing`
(destructive) and `Cancel`.

Both replace `OwnerAppModel.showingRotateConfirmation` and
`showingRevokeConfirmation`, which currently drive nothing.

#### 7.2.6 Paired viewers

`PairedViewerRow.swift`. Backed by `StatusTransport.listViewers()`, loaded when
the Sharing section appears and refreshed after owner actions.

```
  Viewers (up to 5)
  ┌──────────────────────────────────────────────────────┐
  │ 👤 Paired 3 days ago                   Remove Delete │
  │ 👤 Paired 2 weeks ago                  Remove Delete │
  └──────────────────────────────────────────────────────┘
```

The group also says `Five people or devices can watch at the same time.`.
Show only what is true, which here is less than you would like. `ViewerRecord`
has exactly three fields, because `list_viewers()` returns exactly three
columns: `viewer_user_id`, `created_at`, `revoked_at`. There is no name and
there is no last-seen timestamp anywhere in the schema.

So the row is one line: `Paired {relative} ago`, plus trailing `Remove` and
`Delete` buttons in `.link` style. `Remove` soft-revokes immediately. `Delete`
has its own destructive confirmation and permanently removes the binding. Do
not render a second data column. An earlier draft of this plan specified `Last
seen 2h ago` and `Never opened`; that data still does not exist.

The RPC returns active, non-expired rows only, capped at five, so a removed
or expired viewer must not reappear.

Loading: three `MPSkeleton` rows, not a spinner. Failure: an inline
`MPRow` reading `Can't load the list right now.` with a `Try again` button.
Empty (a link exists, nobody has used it): one row reading `Nobody has used the
link yet.`

### 7.3 This Mac

```
This Mac

  ┌──────────────────────────────────────────────────────┐
  │ ⚠ Meeting Pulse is not in your Applications folder.  │
  │   Move it there so it keeps running after updates.   │
  └──────────────────────────────────────────────────────┘

  Your name
  ┌──────────────────────────────────────────────────────┐
  │ Name          [ Mohit                            ]   │
  │               Shown on the page as "Mohit is in a    │
  │               meeting". Leave it blank to stay       │
  │               unnamed.                               │
  └──────────────────────────────────────────────────────┘

  Startup
  ┌──────────────────────────────────────────────────────┐
  │ Open at login                              (•)       │
  │ Open the window at login                   ( )       │
  └──────────────────────────────────────────────────────┘

  If you lose this Mac
  ┌──────────────────────────────────────────────────────┐
  │ 🔑 Recovery phrase                     [ Show ]      │
  │    A code that lets you take over from a new Mac.    │
  │    Mac. Write them down somewhere safe.              │
  └──────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────┐
  │ Delete everything                                    │
  │ Removes your status, the viewer link, and the        │
  │ recovery phrase. This cannot be undone.              │
  │                                     [ Delete... ]    │
  └──────────────────────────────────────────────────────┘
```

#### 7.3.1 Install location banner

Rendered when `store.installLocationIsValid == false`. `MPBanner(.caution)`.

Today this is not merely undisplayed, it is unreachable.
`AppLaunchCoordinator.start` has `guard InstallLocation().isValid() else { state
= .wrongInstallLocation; return }`, which aborts launch before the runtime, the
store, or any window exists. There is nothing left to render a banner in.

So T12 has two parts, and the first one is a behaviour change: make the guard
non-fatal. Set `store.installLocationIsValid = false` and continue starting the
app. Running from `~/Downloads` degrades the experience, because a translocated
or moved bundle can lose its Accessibility grant, but it does not stop Meeting
Pulse from working, and refusing to start with no visible explanation is worse
than the problem it avoids.

Keep the `NSLog`. Drop the early `return`.

Headline: `Meeting Pulse is not in your Applications folder.`
Body: `Move it to Applications so it keeps running after updates.`
Button: `Show me in Finder`, calling
`NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])`.

#### 7.3.2 Display name

`TextField` bound to `store.displayName`. Constraints, enforced in the store's
setter, not the view:

- Trim leading and trailing whitespace on commit.
- Cap at 80 characters. `PRODUCT.md` sets the limit; enforce it by truncating
  input, not by showing an error.
- Empty is valid and means "unnamed". Do not require a value.

Debounce the write to the transport by 600ms so typing does not publish eight
times. Show `Saved` in `.secondary` for 1.6s after a successful write, in the
same slot the field's help text occupies, then fade back.

#### 7.3.3 Recovery phrase

`RecoveryPhraseView.swift`. Hidden by default behind a `Show` button. Once
shown:

- Six groups in a 3 × 2 grid, `MPFont.phrase`, each group numbered `1.`-`6.`
  in `.secondary` at 10pt.
- `MPCopyButton` labelled `Copy the phrase`.
- A caution line: `Anyone with this code can take over your status. Keep it
  somewhere only you can reach.`
- Auto-hides after 60 seconds of the window being frontmost, with no warning
  needed. Reset the timer on any interaction inside the group.

Use `PairingCodeFormat`'s companion `RecoveryPhraseFormat.display` for grouping;
do not re-split the string yourself.

The phrase is not words. `RecoveryPhraseFormat.length` is 26 and `display`
groups Crockford Base32 characters in fives, so the value on screen reads
`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-X`: six groups, the last one a single character.
Lay those six groups out in the grid. Earlier drafts of this plan and of the
copy deck both said "twelve words", which was wrong, and any copy you write for
this screen has to say `code` rather than `words`.

#### 7.3.4 Startup

Two toggles.

`Open at login` writes through the existing `SMAppService` path. The failure
case matters: `SMAppService.mainApp.register()` throws when the user has
disabled the login item in System Settings. On failure, revert the toggle and
show an inline `MPRow` subtitle reading `macOS blocked this. Open Login Items in
System Settings to allow it.` with a button calling
`SMAppService.openSystemSettingsLoginItems()` (macOS 13+, documented, preferred
over a URL scheme).

`Open the window at login` is new and defaults off. When off, launching at login
shows only the menu bar icon, which is what almost everyone wants.

It needs a mechanism, because nothing in the codebase provides one today:

- Persist it in `UserDefaults` under `com.meetingpulse.openWindowAtLogin`. It is
  a display preference, not a secret, so it does not belong in local secret storage
  alongside the pairing material.
- Read it in `AppLaunchCoordinator.start`, after onboarding has been determined
  to be complete, and call `openStation()` only when it is true.
- It has no effect on a manual launch. Opening the app from Finder or Spotlight
  always shows the Station, whatever this toggle says, because the user just
  asked for it. Distinguish the two with
  `NSApplication.shared.isRunning`-adjacent state if you must, but the simpler
  route is to have `AppLaunchCoordinator` only consult the toggle on its own
  first pass and let `applicationShouldHandleReopen` handle the rest.

`Open at login` being off makes this toggle meaningless. Disable it, do not hide
it, and leave the label legible.

#### 7.3.5 Danger zone

`DangerZone.swift`. Separated by `MPSpace.vast` (40) from the group above it, so
it cannot be hit by accident while scanning.

`Delete...` opens a sheet, not an alert, because it needs a text field:

```
  ┌────────────────────────────────────────────┐
  │  Delete everything?                        │
  │                                            │
  │  This removes your status, the viewer      │
  │  link, and the recovery phrase from this   │
  │  Mac and from the server. The page anyone  │
  │  has open will stop working.               │
  │                                            │
  │  Type delete to confirm.                   │
  │  [                                    ]    │
  │                                            │
  │              [ Cancel ]  [ Delete ]        │
  └────────────────────────────────────────────┘
```

The `Delete` button is disabled until the field contains exactly `delete`,
case-insensitive, trimmed. This requirement is in `HANDOFF.md`; do not
substitute a two-tap alert.

After deletion succeeds the app enters a terminal state (defect D6):

- Every section except Privacy is replaced by one `MPEmptyState`:
  headline `Everything is gone.`, body `Meeting Pulse has nothing left to
  publish. Quit and delete the app, or set it up again.`, buttons `Set up again`
  and `Quit Meeting Pulse`.
- The mast shows the generic face with the reason line
  `Everything on this Mac is gone. Quit to finish.`
- The menu bar icon dims to 40% opacity.

### 7.4 Privacy

The only prose section, and the one that has to be exactly true. Read the source
before you write a word of it:

- `MPSync/StatusTransport.swift`, `StatusPayload`: what the Mac sends.
- `supabase/migrations/20260809000100_initial_schema.sql`,
  `get_paired_status()`:
  what a viewer can read.

**These are two different lists, and the gap between them is the product's
whole privacy argument.** The Mac sends five fields. The viewer's projection
returns seven keys, and `supabase/tests/05_viewer_read.sql` asserts both the
key count and that `override_mode` and `device_id` are absent. So the server
holds a little more than the viewer can ever see, on purpose.

Show all three columns. Two would let a reader assume the middle one does not
exist, and the middle one is the interesting part.

```
Privacy

  What leaves this Mac            What she can see          What never leaves
  ┌────────────────────────┐      ┌──────────────────┐      ┌──────────────────┐
  │ ↗ In a meeting, or not │      │ ↗ In a meeting,  │      │ ✕ Window titles  │
  │ ↗ Whether calls are ok │      │   or not         │      │ ✕ Meeting names  │
  │ ↗ Whether you set it   │      │ ↗ Whether calls  │      │ ✕ Who you are    │
  │   by hand              │      │   are okay       │      │   meeting        │
  │ ↗ When that runs out   │      │ ↗ The name you   │      │ ✕ Calendar       │
  │ ↗ The name you chose   │      │   chose          │      │ ✕ Screen         │
  │                        │      │ ↗ When it was    │      │   contents       │
  │                        │      │   last sent      │      │ ✕ Audio          │
  │                        │      │                  │      │ ✕ Anything you   │
  │                        │      │                  │      │   type           │
  └────────────────────────┘      └──────────────────┘      └──────────────────┘

  Meeting Pulse reads the titles of windows that are already open to work
  out whether you are in a call. The titles stay on this Mac.

  The server knows whether you set your status by hand and when that runs
  out. She cannot. The page she loads is not allowed to ask for those.
```

Three columns at 940pt is tight. Below 1100pt window width, stack them
vertically as three `MPGroup`s rather than squeezing. Use a `ViewThatFits`.

Left and middle rows get `arrow.up.right` in `.secondary`. Right rows get
`xmark` in `.secondary`. No red, no green. Colour would turn a factual list
into a scare graphic, and the middle column would have no honest colour anyway.

Two notes on accuracy:

- `StatusPayload.screenSharing` exists, is accepted by the RPC, and is `nil`
  at every one of the three call sites in `MeetingPulseApp.swift`. Do not list
  it. Listing a field the app never populates would be the one kind of error
  this section cannot afford. If someone starts populating it, §16.3's parity
  test fails and forces this copy to be updated.
- `displayName` does not travel in `StatusPayload`. It is set on the device
  record separately and the viewer RPC joins it in. It still leaves the Mac, so
  it belongs in the left column.

`Read how this works` opens the public privacy page if one exists. If it does
not, omit the button rather than linking to a placeholder.

## 8. Onboarding

`Packages/MPUI/Sources/MPUI/Onboarding/`. Replaces the four-paragraph
`OnboardingWindow`. 560 × 480, not resizable, centred.

Three steps. No more. Every step ends with the user having done one thing.

### 8.1 Step 1: what it does

- Glyph: `DayShapeView(shape: .cone, tint: MPColor.paintWhite)` at 72 × 108 on a
  small `plateStorm` plate, the same object they will see for the rest of the
  app's life.
- Headline: `Meeting Pulse tells one person when to call you.`
- Body: `It notices when you are in a Google Meet or a Slack huddle and puts
  "In a meeting" on a private page. Nothing else leaves this Mac.`
- Button: `Get started`.

### 8.2 Step 2: permission

- Glyph: `eye` symbol at 48pt in `MPColor.brass`.
- Headline: `Let the Mac see your window titles.`
- Body: `Meeting Pulse reads the titles of open windows to work out whether you
  are in a call. It never reads what is inside them, and titles stay on this
  Mac.`
- Button: `Open Accessibility settings`.
- Below it, live status: `Waiting...` in `.secondary`, becoming
  `Accessibility is on.` with a `checkmark.seal` in `MPColor.brass`.

**This step advances itself.** Subscribe to `PermissionCoordinator.changes`; the
moment permission is granted, wait 700ms so the change is legible, then advance
to step 3 with the transition in §10 item M18. He should be able to grant
permission in System Settings and find the app already on the next step when he
switches back. Do not make him come back and click Continue.

Provide a `Skip for now` link in `.secondary` at the bottom. Skipping is
allowed; the Watch section will carry the banner until it is resolved.

### 8.3 Step 3: the link

- Glyph: the pairing code cells from §7.2.3, in a skeleton state before the code
  exists.
- Headline: `Send this to whoever needs it.`
- Body: `They open the link and see one word. They do not need an account, and
  they cannot see anything else.`
- Primary: `Create the link`. On success the cells fill in with the landing
  animation (§10, M09) and the button becomes `Copy link`.
- Secondary: `Do this later`, closing the window.

Once a link exists, the button becomes `Open Meeting Pulse`, which closes
onboarding and opens the Station on the Sharing section.

### 8.4 Presentation rules

- Shown on first launch only, when `store.hasCompletedOnboarding == false`.
- Reachable afterwards from the Station's Help menu as `Show setup again`.
- Closing at any step is allowed and does not lose progress.
- Never modal. The menu bar keeps working while it is open.

### 8.5 The step indicator

`StepIndicator.swift`. Three 6pt dots, `MPSpace.tight` apart, bottom-centred.
Current dot is `MPColor.brass` and 8pt; the others are `.secondary` at 30%.
The size and colour change animates with `MPMotion.settle`.

Do not add step numbers, a progress bar, or a percentage. Three dots is the
whole affordance.

---

## 9. The menu bar

`Packages/MPUI/Sources/MPUI/MenuBar/`. This is what gets smaller, and it is the
point of the whole plan.

### 9.1 What it contains

Confirmed with the product owner. Six items and two submenus, in this order:

```
  ┌────────────────────────────────────┐
  │  In a meeting                      │   ← header, disabled
  │  Busy for another 12 minutes       │   ← subtitle
  │ ────────────────────────────────── │
  │  🔴 Set busy                     ▸ │   ← submenu, 7 durations
  │  🟢 Set available                ▸ │   ← submenu, 7 durations
  │  ↺  Back to automatic              │   ← only when an override runs
  │  📞 Calls are okay             ✓   │   ← toggle
  │ ────────────────────────────────── │
  │  ⌂  Open Meeting Pulse        ⌘0   │
  │  ⏻  Quit Meeting Pulse        ⌘Q   │
  └────────────────────────────────────┘
```

Everything else that is in the menu today moves into the window: create link,
copy link, rotate, revoke, settings, recovery phrase, diagnostics, check now,
delete everything. Nine items removed.

### 9.2 Implementation

`.menuBarExtraStyle(.menu)` is backed by `NSMenu`, so only menu-shaped content
renders. These are verified to work: `Button`, `Button(_:systemImage:)`,
`Label`, a `Button` with two `Text` children (title and subtitle), `Menu` as a
submenu, `Divider`, `Section`, `Toggle`, `.keyboardShortcut`, `.badge`, and
`.disabled`. Arbitrary SwiftUI views, `.symbolEffect`, `Gauge`, and sized
`Image`s do **not** render. Every item below stays inside that set.

```swift
public struct MenuBarContent: View {
  let store: PulseStore
  let actions: any PulseActions

  public var body: some View {
    // Header. Disabled so it reads as status, not a control.
    Button {} label: {
      Text(store.plateHeadline)
      Text(store.reasonLine)
    }
    .disabled(true)

    Divider()

    Menu {
      ForEach(ManualOverride.Duration.allCases) { d in
        Button(d.displayName) { actions.setOverride(.busy, d) }
      }
    } label: {
      Label(Strings.Menu.setBusy, systemImage: "person.crop.circle.badge.minus")
    }

    Menu {
      ForEach(ManualOverride.Duration.allCases) { d in
        Button(d.displayName) { actions.setOverride(.available, d) }
      }
    } label: {
      Label(Strings.Menu.setAvailable, systemImage: "person.crop.circle.badge.checkmark")
    }

    if store.hasOverride {
      Button {
        actions.clearOverride()
      } label: {
        Label(Strings.Menu.backToAutomatic, systemImage: "arrow.counterclockwise")
      }
    }

    Toggle(isOn: Binding(
      get: { store.callsOkay },
      set: { actions.setCallsOkay($0) }
    )) {
      Label(Strings.Menu.callsOkay, systemImage: "phone")
    }

    Divider()

    Button {
      actions.openStation()
    } label: {
      Label(Strings.Menu.openStation, systemImage: "house")
    }
    .keyboardShortcut("0", modifiers: .command)

    Button {
      actions.quit()
    } label: {
      Label(Strings.Menu.quit, systemImage: "power")
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}
```

Symbols, fixed:

| Item | Symbol |
|---|---|
| Set busy | `person.crop.circle.badge.minus` |
| Set available | `person.crop.circle.badge.checkmark` |
| Back to automatic | `arrow.counterclockwise` |
| Calls are okay | `phone` |
| Open Meeting Pulse | `house` |
| Quit Meeting Pulse | `power` |

`Back to automatic` appears only when an override is running. A permanently
disabled item teaches nothing; an item that appears when it becomes meaningful
teaches the model.

The header's two `Text` children render as an `NSMenuItem` title and subtitle.
Verify this at build time (§16.1, V1); if the subtitle does not render on the
target OS, fall back to a single `Text` joining the two with a period and a
space, and record the finding in `docs/decisions/`.

### 9.3 The icon

`MenuBarIcon.swift`. This replaces `HeartThreadMenuIcon` (lines 794-929), which
hand-draws an `NSImage` with `NSBezierPath` and sets `isTemplate = false` so it
can carry a coloured status dot.

**Change it to a template image whose shape carries the state.** Two reasons,
both binding:

1. The macOS HIG specifies menu bar extras as template images: black and clear,
   with the system applying tint, vibrancy, and the menu bar's own appearance. A
   coloured icon breaks in dark menu bars, under Reduce Transparency, and on
   displays with a wallpaper-tinted bar.
2. `PRODUCT.md` states that state is never conveyed by colour alone. A coloured
   dot in the menu bar is the one place in this product where it currently is.

So the icon becomes the mast itself, at 18 × 18 in a 22 × 22 canvas, which ties
the menu bar to the plate and the viewer's board in one move:

| Face | Icon |
|---|---|
| `.meeting` | Cone hoisted on the mast |
| `.callOkay` | Pennant flying from a bare pole |
| `.generic` | Bare mast with its yard |
| deleted | Bare mast at 40% opacity |

The three shapes are the same geometry as the plate, at 18pt. They are already
distinguishable at that size because they differ in silhouette, not in detail:
a solid triangle, a flag, and an empty cross. Verify at 1x and 2x (§16.1, V2).

```swift
public struct MenuBarIcon: View {
  let face: PlateFace
  let label: String            // store.plateHeadline, passed in
  let isDimmed: Bool           // true after deletion
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public var body: some View {
    DayShapeView(shape: face.dayShape, tint: .primary)
      .frame(width: 18, height: 18)
      .opacity(isDimmed ? 0.4 : 1)
      .animation(reduceMotion ? nil : MPMotion.hoist, value: face)
      .accessibilityLabel(label)
  }
}
```

Inside the menu bar, `DayShapeView` takes `tint: .primary` instead of
`paintWhite`, which is the only difference from the plate. Nothing in a day
shape was ever coloured, so the mark is already monochrome and templatable
without a second code path. That is the payoff for keeping the shapes tint
parameterised rather than hard-coding `paintWhite` inside them.

**The heart-thread mark is not deleted.** It stays as the app icon, in
`Assets.xcassets`, on the Dock when the Station is open, in About, and at the
top of onboarding. It is the brand; it is just not the status indicator.

Icon geometry: 18 × 18 drawn inside a 22 × 22 image. 22pt is the conventional
menu bar item height and 18pt the conventional glyph size; neither is a
documented constant, so verify visually against a system item such as Wi-Fi
before shipping (§16.1, V2).

### 9.4 Animating the label

There is no documented support for animating a `MenuBarExtra` label, and the
label is hosted inside an `NSStatusItem` rather than a normal SwiftUI window.
Treat this as unverified until you see it run.

- Implement the transition with `.animation(MPMotion.hoist, value: face)` on
  SwiftUI `Shape`s. Do not use `.symbolEffect`; it does not render in menu bar
  extras.
- **One-shot only, on state change.** Never a continuous idle loop. A repeating
  animation in the menu bar keeps the window server awake and costs battery for
  no information.
- Verification task V3 (§16.1): change state and watch the bar. If the shapes do
  not animate, ship the instant swap and record it in `docs/decisions/`. An
  un-animated correct icon is fine; a hack that redraws an `NSImage` on a timer
  is not.

---

## 10. Motion

Motion here has one job: make the mast feel like a physical instrument that
responds to what he does. It is never decoration, and it never delays him.

### 10.1 Rules

1. Everything resolves to one of the six tokens in §4.5. A view that writes
   `.easeInOut(duration: 0.3)` has broken the system.
2. Nothing on this surface animates longer than 250ms except the two springs,
   whose perceptual settle is inside that band.
3. **No load choreography.** Nothing staggers in when a section appears. The
   Station is a working surface, not a presentation. The only entrance
   animations in the app are M09 and M18, both of which mark a thing the user
   just caused.
4. Every animation is gated on `accessibilityReduceMotion`. With Reduce Motion
   on, every state change still happens, instantly.

   The code samples throughout this document write the gate out longhand as
   `reduceMotion ? nil : MPMotion.hoist`, because it is clearer to read in
   isolation. In the implementation, wrap it once:

   ```swift
   extension View {
     func mpAnimation<V: Equatable>(_ a: Animation, value: V) -> some View {
       modifier(MPAnimationModifier(animation: a, value: value))
     }
   }
   ```

   The modifier reads `\.accessibilityReduceMotion` itself and passes `nil`
   when it is on. One place to get it right, and a grep for
   `accessibilityReduceMotion` outside `Theme/` becomes a review signal.
5. Hover feedback is `MPMotion.quick` (150ms) or faster. Anything slower feels
   like lag.
6. `.geometryGroup()` on any container whose children animate position, so
   child animations do not fight the parent's layout pass.

### 10.2 The catalogue

Twenty interactions. Each is a build item; §15 references them by ID.

| ID | Interaction | Trigger | Implementation | Token |
|---|---|---|---|---|
| M01 | **The hoist** | Plate face changes | Plate fill and rim cross-fade; whole plate scales 0.985 → 1.0 | `hoist` |
| M02 | **Day-shape hoist** | Plate face changes | Outgoing shape scales to 0.9 and fades while translating up 6pt; incoming enters from 6pt below at 0.9. `.asymmetric` transition, `.combined(with: .opacity)` | `hoist` |
| M03 | **Headline swap** | Headline text changes | `.contentTransition(.opacity)` with `.animation(hoist, value: headline)`. Not `.blurReplace`; at 30pt it smears | `hoist` |
| M04 | **Countdown roll** | Override minute count ticks | `.contentTransition(.numericText(countsDown: true))` on the reason line. macOS 13+ | `chalk` |
| M05 | **Mode segment** | User picks a segment | System `.segmented` picker animates its own knob. Add nothing. The visible response is M01 on the plate | system |
| M06 | **Duration row reveal** | Mode leaves or enters `.automatic` | `.push(from: .top).combined(with: .opacity)` in, `.opacity` out. Asymmetric because growth should feel physical and collapse should not linger | `settle` |
| M07 | **Pennant hoist** | Calls-are-okay toggled while busy | A full face change, so M01 and M02 already cover it. The flag reads as unfurling because the cone leaves downward-scaled while the pennant enters. Add nothing | `hoist` |
| M08 | **Copy confirm** | Copy button tapped | `doc.on.doc` → `checkmark` via `.contentTransition(.symbolEffect(.replace))`; label swaps to `Copied`; reverts after 1.6s | `quick` |
| M09 | **Code landing** | Pairing code first appears | Ten cells scale 0.86 → 1.0 and fade in, 28ms stagger by index. Total 252ms + 220ms = under 500ms | `land` |
| M10 | **Source pulse** | A source observation flips | The row's `MPStateChip` dot scales to 1.25 and back once. `.symbolEffect(.bounce, value:)` on the leading symbol | `settle` |
| M11 | **Row hover** | Pointer enters an `MPRow` | Background fills to `.quaternary`. `.onHover` + `withAnimation`. `.hoverEffect` does not exist on macOS | `quick` |
| M12 | **Section switch** | Sidebar selection changes | Detail content cross-fades via `.id(store.section)` + `.transition(.opacity)`. No slide; a slide implies spatial order the sections do not have | `leaf` |
| M13 | **Banner arrival** | A banner condition becomes true | `.push(from: .top).combined(with: .opacity)`, and `.geometryGroup()` on the parent so the content below slides rather than jumps | `settle` |
| M14 | **Danger arming** | Confirmation field reaches `delete` | Delete button's tint animates from `.secondary` to `.red` and it becomes enabled. The colour change *is* the feedback | `chalk` |
| M15 | **Terminal dim** | Deletion completes | Whole window content fades to 40% over 400ms, then the empty state fades in. The one place a longer duration is right: it marks an ending | custom 0.4s, `.easeOut` |
| M16 | **Refresh spin** | Check-now tapped | Toolbar icon rotates 360° once. `.rotationEffect` driven by a counter with `withAnimation(.linear(duration: 0.6))`. Not `.rotate`; that symbol effect is macOS 15 | custom 0.6s linear |
| M17 | **Skeleton sweep** | Viewer list loading | A `LinearGradient` mask translating left to right, 1.4s, repeating. The one permitted repeating animation, and it stops the instant data arrives | custom 1.4s |
| M18 | **Onboarding advance** | Permission granted | After 700ms: status line swaps to `Accessibility is on.` with M08's symbol replace, then the step content pushes left while the next pushes in from the right | `settle` |
| M19 | **Focus ring** | Keyboard focus lands | System focus ring, but `.tint(MPColor.brass)` on the container so it matches the world. Do not draw a custom ring | system |
| M20 | **QR expand** | QR code clicked | Popover with `.scaleEffect` from 0.94 and `.opacity`, anchored at the source | `settle` |

### 10.3 Worked example: the hoist

M01 and M02 fire together and are the app's signature. Everything else is
supporting cast. Get these exactly right.

```swift
struct DayShapeView: View {
  let shape: DayShape
  let tint: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      switch shape {
      case .cone:    ConeShape(tint: tint).transition(hoistTransition)
      case .pennant: PennantShape(tint: tint).transition(hoistTransition)
      case .mast:    MastShape(tint: tint).transition(hoistTransition)
      }
    }
    .animation(reduceMotion ? nil : MPMotion.hoist, value: shape)
    .geometryGroup()
  }

  private var hoistTransition: AnyTransition {
    .asymmetric(
      insertion: .offset(y: 6).combined(with: .scale(scale: 0.9)).combined(with: .opacity),
      removal:   .offset(y: -6).combined(with: .scale(scale: 0.9)).combined(with: .opacity)
    )
  }
}
```

The direction is deliberate. The outgoing shape rises and the incoming shape
rises into place from below, so the movement reads as one thing being hauled up
a mast, not two things swapping. Reverse either offset and it becomes a
crossfade with extra steps.

### 10.4 What not to build

- No parallax, no scroll-driven transforms, no `.scrollTransition`. This is a
  form with four short pages.
- No `PhaseAnimator` or `.keyframeAnimator`. Both are available at macOS 14, and
  neither has a job here. Multi-phase animation on a settings surface is
  showmanship.
- No `.wiggle`, `.breathe`, or `.rotate` symbol effects. All three are macOS 15
  and would need availability gates for effects the surface does not need.
- No Liquid Glass. `.glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass)`, `ToolbarSpacer`, and `backgroundExtensionEffect` are
  all macOS 26. Do not add gates for them.
- No continuous idle animation anywhere, above all in the menu bar.

---

## 11. State model

### 11.1 `PulseStore`

`Store/PulseStore.swift`. The single source of view state, and the only object
views observe. It holds values, never services.

```swift
@MainActor @Observable
public final class PulseStore {
  // Mast
  public var plateFace: PlateFace = .generic
  public var plateHeadline: String = ""
  public var reasonLine: String = ""
  public var reasonTone: ReasonTone = .info
  public var mode: PulseMode = .automatic
  public var preferredDuration: ManualOverride.Duration = .m30
  public var overrideExpiry: Date?
  public var callsOkay: Bool = false
  public var displayName: String = ""

  // Watch
  public var accessibilityGranted: Bool = false
  public var meet: SourceObservation?
  public var slack: SourceObservation?
  public var meetSeenAt: Date?
  public var slackSeenAt: Date?
  public var statusReason: StatusReason?
  public var idleCheckInterval: Duration = .seconds(20)
  public var activeCheckInterval: Duration = .seconds(5)

  // Publishing
  public var publishState: PublishState = .never
  public var lastPublished: Date?
  public var syncState: SyncState = .idle
  public var isPublishing: Bool = false
  public var isOnline: Bool = true

  // Sharing
  public var pairingCode: String?
  public var viewerLinks: [URL] = []
  public var viewers: Loadable<[ViewerSummary]> = .idle

  // This Mac
  public var launchAtLogin: Bool = false
  public var openWindowAtLogin: Bool = false
  public var recoveryPhrase: String?
  public var installLocationIsValid: Bool = true

  // Lifecycle
  public var section: StationSection = .watch
  public var setupFailure: String?
  public var hasCompletedOnboarding: Bool = false
  public var deleteCompleted: Bool = false
  public var lastError: PulseError?

  // Derived
  public var hasViewerLink: Bool { !viewerLinks.isEmpty }
  public var primaryViewerLink: URL? { viewerLinks.first }
  public var hasOverride: Bool { mode != .automatic }

  /// The freshness gate the viewer applies, mirrored exactly.
  /// `STALE_AFTER_SECONDS` in `viewer/src/lib/freshness.ts` is 180.
  public var isFresh: Bool {
    guard let lastPublished else { return false }
    return Date.now.timeIntervalSince(lastPublished) <= 180
  }

  public var needsAttention: Bool {
    setupFailure != nil || !accessibilityGranted || !installLocationIsValid
      || syncState == .retrying || syncState == .superseded
  }
}
```

`reasonLine` is computed by a pure function so it can be unit-tested without a
view:

```swift
public enum ReasonLineBuilder {
  public static func line(for store: PulseStore) -> (String, ReasonTone)
}
```

Implement the precedence table in §6.4 there, in order, and test every row
(§16.2).

### 11.2 `PulseActions`

`Store/PulseActions.swift`. Everything a view can ask for. The app target
implements it over `OwnerRuntime`; `MPUI` never sees a transport.

```swift
@MainActor
public protocol PulseActions: AnyObject {
  func setOverride(_ state: State, _ duration: ManualOverride.Duration)
  func clearOverride()
  func setCallsOkay(_ on: Bool)
  func setDisplayName(_ name: String) async
  func checkAndPublishNow() async

  func createViewerLink() async
  func rotateViewerLink() async
  func revokeViewerAccess() async
  func loadViewers() async
  func removeViewer(id: UUID) async     // ViewerSummary.id, passed to revokeViewer(_:)
  func deleteViewer(id: UUID) async     // ViewerSummary.id, passed to delete_viewer(_:)

  func setLaunchAtLogin(_ on: Bool) throws
  func setOpenWindowAtLogin(_ on: Bool)
  func revealRecoveryPhrase() async
  func deleteEverything() async

  func openAccessibilitySettings() -> Bool
  func openLoginItemsSettings()
  func revealInFinder()

  func openStation()
  func openStation(section: StationSection)
  func showOnboarding()
  func quit()
}
```

Two rules for the conformance in the app target:

- Every method that can fail sets `store.lastError` with a specific case. Never
  the blanket network string (defect D3).
- Every method that changes published state updates the store **before**
  awaiting the network, then reconciles. He toggles Calls-are-okay and the
  pennant rises immediately; if the publish fails, the rail says so. The
  interface should never wait on a round trip to acknowledge a click.

### 11.3 Value types

`Store/PulseSnapshot.swift`:

```swift
public enum PulseMode: Hashable, Sendable { case busy, automatic, free }

public enum PublishState: Equatable, Sendable {
  case never, publishing
  case published(at: Date)
  case retrying, offline, superseded
}

public enum SyncState: Equatable, Sendable { case idle, retrying, superseded }
public enum ReasonTone: Sendable { case info, caution, alert }

public enum Loadable<T: Sendable>: Sendable {
  case idle, loading
  case loaded(T)
  case failed(String)
}

public struct ViewerSummary: Identifiable, Sendable {
  public let id: UUID          // ViewerRecord.viewerUserID
  public let pairedAt: Date
}

public enum PulseError: Equatable, Sendable {
  case network            // "Can't reach the server. Retrying."
  case localStorage       // "Meeting Pulse couldn't access its local data."
  case permissionDenied   // "Meeting Pulse can't see your windows yet."
  case invalidPhrase      // "That phrase doesn't match. Check for typos."
  case loginItemBlocked   // "macOS blocked this. Open Login Items to allow it."
  case supersededByAnother
}
```

### 11.4 Wiring: the ten connections

Each of these is a real defect being fixed, not a refactor. §15 gives them task
numbers.

| # | What | Where | How |
|---|---|---|---|
| W1 | `SchedulerReading` → store | `OwnerRuntime.start()` | The reading is already in hand; assign `meet`, `slack`, and `accessibilityGranted` instead of discarding it, and stamp `meetSeenAt`/`slackSeenAt` with `.now`. The reading has no health and no timestamps of its own |
| W2 | `EffectiveStatus.reason` → store | same call site | Assign `store.statusReason`. Drives §6.4 rows 10 and 11 |
| W3 | Heartbeat | `OwnerRuntime.start()` | Call `SyncCoordinator.startHeartbeat(interval: .seconds(60), payload:)`. It has never been called. Defect D1. Note the parameter is a `Duration`, so `interval: 60` will not compile, and 60 is the default anyway. Also note `submit()` awaits the current drain, so a heartbeat tick can block through a full retry backoff: update `store.publishState` before awaiting, per §11.2 |
| W4 | `SyncCoordinator.currentState` | `OwnerRuntime` | Map to `store.syncState`. Drives the rail and the superseded banner. `SyncCoordinator` is an `actor` and `currentState` is a plain property with no stream, so read it right after every `submit()` and every heartbeat tick rather than trying to observe it. Do not add a polling loop |
| W5 | `lastSuccessfulSync` | `OwnerRuntime` | Assign to `store.lastPublished` after every publish |
| W6 | `PermissionCoordinator.changes` | `OwnerRuntime.start()` | Consume the stream in a `Task`. Drives §7.1.2 and onboarding auto-advance |
| W7 | `NetworkMonitor` | `OwnerRuntime.start()` | Instantiate and consume. Sets `store.isOnline`. When offline, the rail says `No network. Waiting.` rather than `Retrying` |
| W8 | `listViewers()` | `PulseActions.loadViewers()` | Call on Sharing appear. First UI this method has ever had |
| W9 | `InstallLocation.isValid()` | `AppLaunchCoordinator` | Assign to `store.installLocationIsValid`. Currently the result is dropped |
| W10 | `AppLaunchCoordinator` observable | app target | Add `@Observable`. Its `LaunchState` currently cannot reach any view. Map `.wrongInstallLocation` to `store.installLocationIsValid` and `.setupRequired(message)` to `store.setupFailure`, which §7.1 renders as an `MPBanner(.alert)` at the top of Watch with the deck's Setup errors copy. Without this, a local storage or recovery failure at launch is completely silent |

W3 is the one to check first. Without it, the freshness UI is describing a
heartbeat that is not running, and the Watch section would confidently report
health for a mechanism that does not exist.

### 11.5 Previews

`Store/PreviewStore.swift`. Every view file ships at least three previews and
they all use these fixtures. A view without previews is not done.

```swift
public extension PulseStore {
  static var previewBusy: PulseStore          // meeting, named, calls okay
  static var previewAutomatic: PulseStore     // watching, nothing detected
  static var previewNoPermission: PulseStore  // banner state
  static var previewNoLink: PulseStore        // first-run empty state
  static var previewRetrying: PulseStore      // network failure
  static var previewSuperseded: PulseStore    // another Mac took over
  static var previewDeleted: PulseStore       // terminal state
}
```

Add a `PreviewActions` no-op conformance of `PulseActions` in the same file so
previews compile without the app target.

---

## 12. Copy

### 12.1 The rule

`HANDOFF.md`: **all user-facing text comes from `docs/copy/deck.md`.** A CI
check greps render code for string literals. No exceptions, including
placeholder text, help strings, accessibility labels, and error messages.

The deck says implementations import from `viewer/src/lib/copy.ts` and
`MPSupport/Strings.swift`. **The Swift file does not exist.** Creating it is
task T02 and blocks every view file.

### 12.2 Structure

`mac-app/Packages/MPSupport/Sources/MPSupport/Strings.swift`:

```swift
public enum Strings {
  public enum App { ... }        // window titles
  public enum Board { ... }      // the plate, mirrored from copy.ts
  public enum Mast { ... }       // mode control, duration, calls okay
  public enum Duration { ... }   // the seven labels
  public enum Menu { ... }       // menu bar items
  public enum Station { ... }    // section titles, toolbar, the rail
  public enum Duration { ... }   // the seven override durations
  public enum Watch { ... }
  public enum Sharing { ... }
  public enum ThisMac { ... }
  public enum Privacy { ... }
  public enum Onboarding { ... }
  public enum Errors { ... }
  public enum A11y { ... }       // VoiceOver-only strings
}
```

Values that interpolate are functions, not format strings:

```swift
public static func meetingNamed(_ name: String) -> String { "\(name) is in a meeting" }
```

### 12.3 New strings

Mirror all of these into `Strings.swift`. The deck is the source; the Swift file
is the port.

`docs/copy/deck.md` already has a `## Owner app` section carrying most of what
follows, added alongside this plan, so T03 is a reconcile rather than a create.
Three of its older subsections are marked superseded and still hold copy that
contradicts this document: `### Menu` (the thirteen-item menu), `### Pairing
window` (the standalone window), and `### Setup errors` (`Move and reopen` /
`Not now`, where §7.3.1 now says `Show me in Finder`). Delete the superseded
text as part of T03 rather than leaving two answers in the binding document. Do
not delete `### Recovery phrase` or `### Delete everything`; reconcile their
wording against §7.3.3 and §7.3.5 instead.

**The plate**, mirrored from `viewer/src/lib/copy.ts`. Verify each against the
viewer before shipping; if they have drifted, the viewer is right.

| Key | Copy | Viewer source |
|---|---|---|
| `Board.meeting` | `In a meeting` | `COPY.board.meeting.headline` |
| `Board.meetingNamed` | `{Name} is in a meeting` | `.headlineWithName` |
| `Board.meetingSupporting` | `Better to wait.` | `.supporting` |
| `Board.callOkay` | `In Meeting, but it's fine to ring through` | `COPY.board.callOkay.headline` |
| `Board.callOkayNamed` | `{Name} is in Meeting, but it's fine to ring through` | `.headlineWithName` |
| `Board.callOkaySupporting` | `He said to go ahead and interrupt.` | `.supporting` |
| `Board.generic` | `Meeting status unavailable` | `COPY.board.generic.headline` |
| `Board.genericSupporting` | `Check again before you call.` | `.supporting` |
| `Board.genericOfflineSupporting` | `Connect to the internet, then check again.` | `.offlineSupporting` |

There is no `genericNamed`. The viewer does not have one. Do not add one.

`Board.callOkay` capitalises "Meeting" mid-sentence and `Board.meeting` does
not. That inconsistency is in the viewer today. Copy it exactly rather than
tidying it here, and raise it separately if it should change. Two surfaces
disagreeing is worse than one surface being slightly odd.

**The mast**

| Key | Copy |
|---|---|
| `Mast.modeBusy` | `Busy` |
| `Mast.modeAuto` | `Automatic` |
| `Mast.modeFree` | `Free` |
| `Mast.durationLabel` | `Until` |
| `Mast.callsOkayLabel` | `Calls are okay` |

**Reason lines**, the §6.4 table

| Key | Copy |
|---|---|
| `Mast.reasonWatching` | `Watching automatically` |
| `Mast.reasonCallsOkaySuffix` | `Calls are okay when you are busy.` |
| `Mast.reasonDetected` | `{Source} call detected` |
| `Mast.reasonUnsure` | `A window looked like a call. Not sure enough.` |
| `Mast.reasonBusyFor` | `Busy for another {n} minutes` |
| `Mast.reasonBusyUntilCleared` | `Busy until you clear it` |
| `Mast.reasonFreeFor` | `Available for another {n} minutes` |
| `Mast.reasonFreeUntilCleared` | `Available until you clear it` |
| `Mast.reasonNoPermission` | `Waiting for Accessibility permission` |
| `Mast.reasonNoLink` | `No one is watching yet. Create a link.` |
| `Mast.reasonRetrying` | `Can't reach the server. Retrying.` |
| `Mast.reasonSuperseded` | `Another Mac took over. This one has stopped.` |
| `Mast.reasonDeleted` | `Everything on this Mac is gone. Quit to finish.` |

Note: `applyLoadedOverride` currently writes `"Available override"`, which is in
no deck and reads like a database column. It is replaced by
`Mast.reasonFreeFor` / `Mast.reasonFreeUntilCleared`. Defect D5.

**The rail**

| Key | Copy |
|---|---|
| `Station.railNever` | `Nothing published yet` |
| `Station.railPublished` | `Published {relative} ago` |
| `Station.railPublishing` | `Publishing...` |
| `Station.railRetrying` | `Can't reach the server. Retrying.` |
| `Station.railOffline` | `No network. Waiting.` |
| `Station.railSuperseded` | `Another Mac is publishing now` |

**Menu bar**

| Key | Copy |
|---|---|
| `Menu.setBusy` | `Set busy` |
| `Menu.setAvailable` | `Set available` |
| `Menu.backToAutomatic` | `Back to automatic` |
| `Menu.callsOkay` | `Calls are okay` |
| `Menu.openStation` | `Open Meeting Pulse` |
| `Menu.quit` | `Quit Meeting Pulse` |

**Sections and toolbar**

| Key | Copy |
|---|---|
| `App.stationWindowTitle` | `Meeting Pulse` |
| `App.setupWindowTitle` | `Set up Meeting Pulse` |
| `Station.watchTitle` | `Watch` |
| `Station.sharingTitle` | `Sharing` |
| `Station.thisMacTitle` | `This Mac` |
| `Station.privacyTitle` | `Privacy` |
| `Station.checkNow` | `Check now` |
| `Station.checkNowHelp` | `Check for a call and publish right away` |

**Watch**

| Key | Copy |
|---|---|
| `Watch.permissionHeader` | `Permission` |
| `Watch.accessibility` | `Accessibility` |
| `Watch.accessibilityGranted` | `Granted` |
| `Watch.accessibilityMissing` | `Not granted` |
| `Watch.accessibilityDetail` | `Meeting Pulse reads window titles. It never reads what is inside them.` |
| `Watch.permissionBannerTitle` | `Meeting Pulse can't see your windows yet.` |
| `Watch.permissionBannerBody` | `Turn on Accessibility so the Mac can read window titles. It never reads what is inside them.` |
| `Watch.openAccessibility` | `Open Accessibility settings` |
| `Watch.openAccessibilityFallback` | `Open System Settings, then Privacy & Security, then Accessibility.` |
| `Watch.sourcesHeader` | `What the Mac watches` |
| `Watch.sourceMeet` | `Google Meet` |
| `Watch.sourceSlack` | `Slack huddles` |
| `Watch.sourceInCall` | `In a call` |
| `Watch.sourceNoCall` | `No call` |
| `Watch.sourceUnsure` | `Can't tell` |
| `Watch.sourceNeverSeen` | `Not seen yet` |
| `Watch.sourceNeverSeenDetail` | `Meeting Pulse will notice the next time you join.` |
| `Watch.sourceSeen` | `{App}, {relative} ago` |
| `Watch.sourceChecked` | `Checked {relative} ago` |
| `Watch.publishingHeader` | `Publishing` |
| `Watch.lastPublished` | `Last published` |
| `Watch.checksRun` | `Checks run` |
| `Watch.checksEvery` | `Every {active}s in a call, {idle}s idle` |
| `Watch.thisMac` | `This Mac` |
| `Watch.thisMacPublishing` | `Publishing` |
| `Watch.thisMacRetrying` | `Retrying` |
| `Watch.thisMacStopped` | `Stopped` |
| `Watch.supersededTitle` | `Another Mac took over.` |
| `Watch.supersededBody` | `Meeting Pulse is running somewhere else. This Mac has stopped publishing.` |

**Sharing**

| Key | Copy |
|---|---|
| `Sharing.emptyTitle` | `No one is watching yet.` |
| `Sharing.emptyBody` | `Create a link and send it to whoever needs to know when to call.` |
| `Sharing.createLink` | `Create the viewer link` |
| `Sharing.linkHeader` | `The link` |
| `Sharing.copyLink` | `Copy link` |
| `Sharing.copyHostLink` | `Copy {host} link` |
| `Sharing.copyCode` | `Copy code` |
| `Sharing.copied` | `Copied` |
| `Sharing.share` | `Share` |
| `Sharing.rotate` | `Create a new link` |
| `Sharing.rotateConfirmTitle` | `Create a new link?` |
| `Sharing.rotateConfirmBody` | `The old link stops working right away. Anyone using it will need the new one.` |
| `Sharing.revoke` | `Stop sharing` |
| `Sharing.revokeConfirmTitle` | `Stop sharing?` |
| `Sharing.revokeConfirmBody` | `The link stops working right away. No one will be able to see your status.` |
| `Sharing.viewersHeader` | `Viewers (up to 5)` |
| `Sharing.viewersBody` | `Five people or devices can watch at the same time.` |
| `Sharing.viewerPaired` | `Paired {relative} ago` |
| `Sharing.viewersEmpty` | `Nobody has used the link yet.` |
| `Sharing.viewersFailed` | `Can't load the list right now.` |
| `Sharing.tryAgain` | `Try again` |
| `Sharing.removeViewer` | `Remove` |
| `Sharing.deleteViewer` | `Delete` |
| `Sharing.deleteViewerTitle` | `Delete viewer?` |
| `Sharing.deleteViewerBody` | `This permanently removes the viewer binding. The person can pair again with the link.` |

**Durations**, used by the picker in §6.5.2 and the menu bar submenus in §9.2

| Key | String |
|---|---|
| `Duration.m15` | `15 minutes` |
| `Duration.m30` | `30 minutes` |
| `Duration.m45` | `45 minutes` |
| `Duration.h1` | `1 hour` |
| `Duration.h2` | `2 hours` |
| `Duration.h4` | `4 hours` |
| `Duration.untilCleared` | `Until I clear it` |

**This Mac**

| Key | Copy |
|---|---|
| `ThisMac.nameHeader` | `Your name` |
| `ThisMac.nameLabel` | `Name` |
| `ThisMac.nameDetail` | `Shown on the page as "{Name} is in a meeting". Leave it blank to stay unnamed.` |
| `ThisMac.nameSaved` | `Saved` |
| `ThisMac.startupHeader` | `Startup` |
| `ThisMac.launchAtLogin` | `Open at login` |
| `ThisMac.openWindowAtLogin` | `Open the window at login` |
| `ThisMac.recoveryHeader` | `If you lose this Mac` |
| `ThisMac.recoveryLabel` | `Recovery phrase` |
| `ThisMac.recoveryDetail` | `A code that lets you take over from a new Mac. Write it down somewhere safe.` |
| `ThisMac.recoveryShow` | `Show` |
| `ThisMac.recoveryHide` | `Hide` |
| `ThisMac.recoveryCopy` | `Copy the phrase` |
| `ThisMac.recoveryWarning` | `Anyone with this code can take over your status. Keep it somewhere only you can reach.` |
| `ThisMac.installTitle` | `Meeting Pulse is not in your Applications folder.` |
| `ThisMac.installBody` | `Move it to Applications so it keeps running after updates.` |
| `ThisMac.installAction` | `Show me in Finder` |
| `ThisMac.deleteHeader` | `Delete everything` |
| `ThisMac.deleteBody` | `Removes your status, the viewer link, and the recovery phrase. This cannot be undone.` |
| `ThisMac.deleteButton` | `Delete...` |
| `ThisMac.deleteSheetTitle` | `Delete everything?` |
| `ThisMac.deleteSheetBody` | `This removes your status, the viewer link, and the recovery phrase from this Mac and from the server. The page anyone has open will stop working.` |
| `ThisMac.deleteConfirmPrompt` | `Type delete to confirm.` |
| `ThisMac.deletedTitle` | `Everything is gone.` |
| `ThisMac.deletedBody` | `Meeting Pulse has nothing left to publish. Quit and delete the app, or set it up again.` |
| `ThisMac.setUpAgain` | `Set up again` |

**Privacy**

| Key | Copy |
|---|---|
| `Privacy.leavesHeader` | `What leaves this Mac` |
| `Privacy.seesHeader` | `What she can see` |
| `Privacy.staysHeader` | `What never leaves this Mac` |
| `Privacy.leaves1` | `In a meeting, or not` |
| `Privacy.leaves2` | `Whether calls are okay` |
| `Privacy.leaves3` | `Whether you set it by hand` |
| `Privacy.leaves4` | `When that runs out` |
| `Privacy.leaves5` | `The name you chose` |
| `Privacy.sees1` | `In a meeting, or not` |
| `Privacy.sees2` | `Whether calls are okay` |
| `Privacy.sees3` | `The name you chose` |
| `Privacy.sees4` | `When it was last sent` |
| `Privacy.stays1` | `Window titles` |
| `Privacy.stays2` | `Meeting names` |
| `Privacy.stays3` | `Who you are meeting` |
| `Privacy.stays4` | `Calendar events` |
| `Privacy.stays5` | `Screen contents` |
| `Privacy.stays6` | `Audio` |
| `Privacy.stays7` | `Anything you type` |
| `Privacy.explanation` | `Meeting Pulse reads the titles of windows that are already open to work out whether you are in a call. The titles stay on this Mac.` |
| `Privacy.boundary` | `The server knows whether you set your status by hand and when that runs out. She cannot. The page she loads is not allowed to ask for those.` |

**VoiceOver only.** These are never drawn. See §13.3.

| Key | String |
|---|---|
| `A11y.modeControl` | `Status mode` |
| `A11y.pairingCode` | `Pairing code, {spelled} ` |
| `A11y.plate` | `{headline}. {supporting}` |
| `A11y.rail` | `Publishing status` |

**Onboarding**

| Key | Copy |
|---|---|
| `Onboarding.step1Title` | `Meeting Pulse tells one person when to call you.` |
| `Onboarding.step1Body` | `It notices when you are in a Google Meet or a Slack huddle and puts "In a meeting" on a private page. Nothing else leaves this Mac.` |
| `Onboarding.step1Action` | `Get started` |
| `Onboarding.step2Title` | `Let the Mac see your window titles.` |
| `Onboarding.step2Body` | `Meeting Pulse reads the titles of open windows to work out whether you are in a call. It never reads what is inside them, and titles stay on this Mac.` |
| `Onboarding.step2Waiting` | `Waiting...` |
| `Onboarding.step2Granted` | `Accessibility is on.` |
| `Onboarding.skip` | `Skip for now` |
| `Onboarding.step3Title` | `Send this to whoever needs it.` |
| `Onboarding.step3Body` | `They open the link and see one word. They do not need an account, and they cannot see anything else.` |
| `Onboarding.step3Action` | `Create the link` |
| `Onboarding.later` | `Do this later` |
| `Onboarding.finish` | `Open Meeting Pulse` |

### 12.4 Errors

Every failure names what to do next. Nine `catch` blocks currently share one
string; that ends here (defect D3).

| Key | Copy |
|---|---|
| `Errors.network` | `Can't reach the server. Retrying.` |
| `Errors.offline` | `No network. Waiting.` |
| `Errors.localStorage` | `Meeting Pulse couldn't access its local data. Try again.` |
| `Errors.permissionDenied` | `Meeting Pulse can't see your windows yet.` |
| `Errors.invalidPhrase` | `That phrase doesn't match. Check for typos.` |
| `Errors.loginItemBlocked` | `macOS blocked this. Open Login Items in System Settings to allow it.` |
| `Errors.linkFailed` | `Couldn't create the link. Try again.` |
| `Errors.viewersFailed` | `Can't load the list right now.` |

### 12.5 Words this app does not use

From `docs/copy/deck.md`, binding. Grep the diff for every one before you open a
PR.

seamless, effortless, powerful, robust, leverage, utilize, delve, elevate,
unlock, Oops, Uh oh, Something went wrong, An error occurred, Please note that,
In order to, At this point in time, Online, Offline, Active, Idle,
`Status: Green`, and **em dashes**. Replace an em dash with a period, a comma, or
a colon.

Also banned in this surface specifically: `Enabled`, `Disabled`, `N/A`,
`Unknown`, `Error`, `Failed`, `Success`, and any label that is a variable name
with the underscores taken out.

---

## 13. Accessibility

`PRODUCT.md` sets the bar. This section makes it concrete for the new surface.

### 13.1 Contrast

Every pair in §4.1 is measured in both appearances and passes. Three rules that
are easy to break:

- `0.78` is the supporting-text opacity and it is not adjustable. Four of the
  six composited pairs clear 4.5:1 by less than 0.05. Lowering it to `0.75`
  fails in light mode on all three plates.
- Measure light mode. The failures this plan corrects were all invisible to a
  dark-mode-only check, and the worst of them was on the plate face that is on
  screen most of the day.
- Do not put `chalk` on a plate. It is a ground colour, and its light variant
  `#3A403E` is nearly the same value as `plateBare` dark.

Re-measure after any colour change. Do not assume a small tweak is safe.

### 13.2 Never colour alone

Enforced structurally, not by convention:

| Signal | Colour | Shape | Word |
|---|---|---|---|
| Busy | storm plate | cone | `In a meeting` |
| Busy, calls okay | amber plate | pennant | `In Meeting, but it's fine to ring through` |
| Everything else | bare plate | bare mast | `Meeting status unavailable` |
| Source active | filled chip | filled dot | `In a call` |
| Attention | brass | `exclamationmark.triangle` | the banner text |

Storm and amber are the closest pair in the palette and the pair a red-green
colour blind viewer is least likely to separate. That is exactly why the shape
carries the difference: a solid triangle against a flag is unmistakable at any
size, including 18pt in the menu bar.

Verification: take a screenshot of every section, run it through a greyscale
filter, and confirm every state is still readable. If any is not, the build is
not done.

### 13.3 VoiceOver

The plate is one element, not five:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(headline)            // "Mohit is in a meeting"
.accessibilityValue(face.supporting(isOnline: isOnline))  // "Better to wait."
.accessibilityHint(reasonLine)           // "Busy for another 12 minutes"
```

The day shape is decorative relative to that label and gets
`.accessibilityHidden(true)`. Announcing "cone shape" helps nobody.

The mode control uses the system segmented picker, which is already correct.
Add `.accessibilityLabel(Strings.A11y.modeControl)` to give the group a name:
`How your status is decided`.

Source rows combine into one element per row:

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("Google Meet")
.accessibilityValue("In a call. Checked 3 seconds ago.")
```

The pairing code must not be read character by character with cell boundaries
announced. Set one label on the group:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(Strings.A11y.pairingCode)          // "Viewer code"
.accessibilityValue(code.map(String.init).joined(separator: " "))
```

Announce state changes that the user did not cause:

```swift
AccessibilityNotification.Announcement(store.plateHeadline).post()
```

Fire this only when `plateFace` changes and the window is frontmost. Do not
announce every heartbeat.

### 13.4 Keyboard

Full Keyboard Access must reach every control. Tab order in the Station:

1. Mode control (three segments, arrow keys within)
2. Duration picker, when present
3. Calls-are-okay toggle
4. Section list (arrow keys within)
5. Detail pane controls, top to bottom
6. Toolbar

Shortcuts, all registered through `.commands`:

| Shortcut | Action |
|---|---|
| `⌘0` | Open Meeting Pulse |
| `⌘R` | Check now |
| `⌘1`-`⌘4` | Jump to Watch, Sharing, This Mac, Privacy |
| `⌘W` | Close the window, app keeps running |
| `⌘Q` | Quit |
| `Esc` | Dismiss a sheet or popover |

`⌘W` must not quit. It is an accessory app; closing the window is normal.

`StationCommands` is a `Commands` value in
`Station/StationCommands.swift`, attached with `.commands` on the Station's
`Window` scene (§5.4). It holds a reference to `PulseStore` and `PulseActions`
and does two things:

```swift
public struct StationCommands: Commands {
  let store: PulseStore
  let actions: any PulseActions

  public var body: some Commands {
    CommandGroup(after: .toolbar) {
      Button(Strings.Station.checkNow) { Task { await actions.checkNow() } }
        .keyboardShortcut("r")
      Divider()
      ForEach(StationSection.allCases) { section in
        Button(section.title) { store.section = section }
          .keyboardShortcut(section.shortcut)   // "1" ... "4"
      }
    }
  }
}
```

This is why §11.1 holds `section` on the store rather than in a `@State` on
`StationWindow`: a `Commands` value is outside the view hierarchy and cannot
reach view-private state. `StationSection` therefore needs `CaseIterable` and
`Identifiable` alongside its `title` and `symbol`.

Do not build a custom focus ring. Use the system one and tint the container
`MPColor.brass` (M19).

### 13.5 Larger text and Reduce Transparency

- Every font uses `Font.system(size:weight:)`, which scales. Test at the largest
  Accessibility text size: the plate must not clip, and the code cells must
  grow with the glyph rather than truncating it.
- Under Reduce Transparency, the app has nothing to fall back to because it uses
  no `Material`. This is intentional. Do not add one.
- Under Increase Contrast, the plate rim goes from 2pt to 3pt and its opacity to
  1.0. Read `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`.

---

## 14. Xcode project changes

The project is `mac-app/MeetingPulse.xcodeproj`, hand-written,
`objectVersion = 60`, with sequential placeholder UUIDs of the form
`A000000000000000000000NN`. Follow the existing pattern exactly. Do not
regenerate the file, do not open and re-save it in Xcode before the edits are
in, and do not introduce randomly generated UUIDs.

### 14.1 Register the MPUI package

Five edits, mirroring how `MPSync` is registered. Use the next free UUIDs:
`...0074`, `...0084`, `...0094`.

1. `PBXBuildFile`:
```
A00000000000000000000094 /* MPUI in Frameworks */ = {isa = PBXBuildFile; productRef = A00000000000000000000084 /* MPUI */; };
```

2. `XCLocalSwiftPackageReference`:
```
A00000000000000000000074 /* XCLocalSwiftPackageReference "Packages/MPUI" */ = {
  isa = XCLocalSwiftPackageReference;
  relativePath = Packages/MPUI;
};
```

3. `XCSwiftPackageProductDependency`:
```
A00000000000000000000084 /* MPUI */ = {
  isa = XCSwiftPackageProductDependency;
  package = A00000000000000000000074 /* XCLocalSwiftPackageReference "Packages/MPUI" */;
  productName = MPUI;
};
```

4. Add `A00000000000000000000074` to the project's `packageReferences` array.
5. Add `A00000000000000000000084` to the target's `packageProductDependencies`
   array, and `A00000000000000000000094` to the Frameworks build phase `files`.

Verify with `xcodebuild -list` before writing any Swift. A malformed pbxproj
fails in a way that looks like a Swift error and will cost an hour.

### 14.2 Fix the LSUIElement inconsistency

`project.pbxproj` sets a bare `LSUIElement = YES` in both build configurations
(lines 280 and 301). `MeetingPulse/Info.plist` sets
`<key>LSUIElement</key><false/>`.

There is no ambiguity about which wins, though it looks like there is. The build
setting is a plain user-defined setting, not `INFOPLIST_KEY_LSUIElement`, and
`GENERATE_INFOPLIST_FILE = NO` with an explicit `INFOPLIST_FILE`, so nothing
merges the setting into the plist. The plist wins outright: **`LSUIElement` is
false today**, and the app is only accessory because `init()` calls
`setActivationPolicy(.accessory)` at runtime.

That has a visible cost. The app launches with a Dock icon and a menu bar entry
for the moment before `init()` runs, which is the flicker on cold launch.

Resolve it: set `<true/>` in `Info.plist`. Either promote the build setting to
`INFOPLIST_KEY_LSUIElement` or delete it, but do not leave a dead setting that
reads as if it were doing something.

Consequence to verify: with `LSUIElement` genuinely true for the first time, the
Station window opening needs `NSApp.activate()` first, which §5.8 already
specifies. This matters more than it did before, because until now the app was
launching as a regular app and demoting itself, and it may have been getting
focus for free. Confirm the window actually takes focus, including on a fresh
launch where the app has never been frontmost. This is V5 in §16.1.

### 14.3 No new resources in the app target

Colour sets live in `Packages/MPUI/Sources/MPUI/Resources/Media.xcassets`, added
by `resources: [.process("Resources")]` in `Package.swift`. Access them with
`Color("Ground", bundle: .module)`. No pbxproj change is needed for any of them,
which is the reason for the package.

No fonts are bundled. See §4.2 and §17.4.

---

## 15. Tasks

Build in this order. Each task states what "done" means. Do not start a task
whose dependencies are unfinished.

### Phase 1: foundation

| ID | Task | Depends | Done when |
|---|---|---|---|
| T01 | Create `Packages/MPUI` and register it in the pbxproj (§14.1) | | `xcodebuild -list` succeeds and a trivial `MPUI` symbol compiles into the app target |
| T02 | Create `MPSupport/Sources/MPSupport/Strings.swift` with every key in §12 | | Every string in §12.3 and §12.4 exists; a test asserts none is empty |
| T03 | Reconcile `docs/copy/deck.md`'s `## Owner app` section with §12.3, deleting the three superseded subsections | | The deck and `Strings.swift` agree key for key; no superseded copy remains; §16.3 test passes |
| T04 | Build `Theme/` (§4.1-4.6): colours, asset catalogue, fonts, spacing, radii, motion, `DayShape` | T01 | All six motion tokens exist; contrast test (§16.3) passes; a preview renders all three day shapes |
| T05 | Delete the `pairing`, `settings`, `recovery`, `diagnostics` scenes and their views; delete `showPairingWindow()` and its `NSPanel` (defect D4) | | The app builds; the menu items that opened them are gone or stubbed |

### Phase 2: state

| ID | Task | Depends | Done when |
|---|---|---|---|
| T06 | `PulseStore`, `PulseSnapshot`, `PulseActions`, `PreviewStore` (§11.1-11.3, 11.5) | T01, T04 | Seven preview fixtures exist and compile inside the package alone |
| T07 | `ReasonLineBuilder` implementing §6.4's precedence table | T06 | All thirteen rows covered by tests (§16.2), row 12a included |
| T08 | Conform the app target to `PulseActions` over `OwnerRuntime` | T06 | Every method routes to real work; none is a stub |
| T09 | W1, W2: surface `SchedulerReading` and `EffectiveStatus.reason` on the store | T08 | `store.meet`, `.slack`, `.accessibilityGranted`, `.statusReason` update every scheduler tick |
| T10 | W6: consume `PermissionCoordinator.changes`, and drop `pollInterval` to `.seconds(1)` while onboarding or Watch is frontmost | T08 | Granting Accessibility in System Settings flips the store within ~1s with no relaunch; the poll returns to 5s when neither is frontmost |
| T11 | W4, W5, W7: `SyncCoordinator` state and `NetworkMonitor` | T08 | Pulling the network makes the rail read `No network. Waiting.` within 5s |
| T12 | W9, W10: make `AppLaunchCoordinator` `@Observable`; surface `installLocationIsValid` | T08 | Running from `~/Downloads` shows the banner in This Mac |
| T13 | Defects D2, D3, D5: remove the pessimistic `connectionLine` default, split the seven `catch` blocks and `AppLaunchCoordinator`'s generic catch into the §12.4 cases, replace `"Available override"` at both lines 372 and 379 | T02, T06 | No two `catch` blocks assign the same string; launch shows no error |
| T14 | Defect D1: call `SyncCoordinator.startHeartbeat(payload:)` (the 60s default is correct) | T08 | A quiet Mac stays fresh past 5 minutes; the viewer does not go stale |

### Phase 3: the mast

| ID | Task | Depends | Done when |
|---|---|---|---|
| T15 | `DayShapeView` and the three `Shape` types (§6.3) | T04 | All three render at 88 × 132 and at 18 × 18; every path string matches `index.astro` character for character, pennant included |
| T16 | `MPPlate` and `PlateFace` (§6.2) | T15, T06 | `PlateFace` has exactly three cases and its initialiser matches `effectiveDisplayState` line for line; a preview shows all five headline permutations |
| T17 | `MastView`: reason line, mode control, duration row, calls-okay switch (§6.1, 6.4-6.6) | T16, T07 | Every control writes through `PulseActions`; the duration row slides |
| T18 | `PublishRail` with the coarse relative formatter (§6.7) | T06 | The timer runs only while the window is visible |
| T19 | Motion M01, M02, M03, M04, M06, M07 | T17 | Each behaves as §10.2 describes; each is instant with Reduce Motion on |

### Phase 4: the station

| ID | Task | Depends | Done when |
|---|---|---|---|
| T20 | `Components/`: all eight shared components (§4.7) | T04 | Each ships all seven states and at least three previews |
| T21 | `StationWindow`, `StationSidebar`, `StationSection`, `StationToolbar`, `StationCommands` (§5.5-5.7) | T17, T20 | Window opens at 940 × 620, sidebar is 288 fixed, `⌘1`-`⌘4` work |
| T22 | `WatchSection` with permission, sources, publishing, and both banners (§7.1) | T21, T09, T11 | Every value comes from a real reading; `Can't tell` never renders as `No call` |
| T23 | `SharingSection`: empty state, code, QR, actions, viewer list (§7.2) | T21 | `listViewers()` is called; loading uses skeletons; both confirmations work |
| T24 | `ThisMacSection`: name, startup, recovery, install banner, danger zone (§7.3) | T21, T12 | Delete requires typing `delete`; login-item failure shows the specific message |
| T25 | Defect D6: the terminal state after deletion (§7.3.5) | T24 | Sections are replaced, the mast reads the deleted line, the menu bar icon dims |
| T26 | `PrivacySection`, three columns (§7.4) | T21 | Columns are five, four, and seven rows per §16.3; no row names `screenSharing`; stacks below 1100pt |
| T27 | Motion M08, M09, M10, M11, M12, M13, M14, M15, M16, M17, M20 | T22-T26 | Each behaves as §10.2 describes; each is instant with Reduce Motion on |

### Phase 5: menu bar and onboarding

| ID | Task | Depends | Done when |
|---|---|---|---|
| T28 | `MenuBarContent`: the six items and two submenus (§9.1-9.2) | T21 | Nine items are gone; `Back to automatic` appears only with an override |
| T29 | `MenuBarIcon`: template rendering, shape-carried state, delete `HeartThreadMenuIcon` (§9.3) | T15 | Legible in light and dark menu bars and under Reduce Transparency; no colour carries state |
| T30 | `OnboardingWindow` with three steps and auto-advance (§8) | T21, T10 | Granting permission in System Settings advances the step without a click |
| T31 | Motion M18 and the step indicator (§8.5) | T30 | Advance is legible; instant with Reduce Motion on |

### Phase 6: verification

| ID | Task | Depends | Done when |
|---|---|---|---|
| T32 | Verifications V1-V5 (§16.1) | T28, T29 | Each has a recorded result; anything that failed has a decision record |
| T33 | Tests (§16.2, 16.3) | T27, T31 | All pass in CI |
| T34 | Accessibility pass (§13) | T33 | Greyscale screenshots readable; VoiceOver walk complete; largest text size does not clip |
| T35 | Update `DESIGN.md` with the owner-app section and the direction contract | T34 | `DESIGN.md` describes the Station as built, not as planned |
| T36 | Write `docs/decisions/` records for the menu bar icon change, the two-register mast, and any verification that failed | T32 | One file per decision, with the reasoning |

---

## 16. Testing

### 16.1 Manual verifications

Five things this plan asserts that the documentation does not confirm. Run each,
record the result, and write a decision record for any that fails.

| ID | Verify | If it fails |
|---|---|---|
| V1 | A menu item with two `Text` children renders as a title and subtitle in a `.menu`-style `MenuBarExtra` on macOS 14 | Join them with `. ` in one `Text` |
| V2 | An 18 × 18 glyph in a 22 × 22 template image is the right optical size next to the Wi-Fi menu item | Adjust the glyph size until it matches; the numbers are conventions, not constants |
| V3 | `.animation` on SwiftUI `Shape`s inside a `MenuBarExtra` label actually animates | Ship the instant swap. Do not build a timer-driven `NSImage` sequence |
| V4 | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` opens the right pane | The fallback text in §7.1.1 is already specified; make sure it appears |
| V5 | `NSApp.activate()` brings the Station forward from a cold `.accessory` launch | Investigate before adding `ignoringOtherApps:`, which is soft-deprecated |

### 16.2 Unit tests

`Packages/MPUI/Tests/MPUITests/`:

- `PlateFaceTests`: `PlateFace(state:callsOkay:isFresh:)` across all twelve
  combinations of three states, two `callsOkay` values, and two freshness
  values. `.meeting` only for `(.busy, false, true)`, `.callOkay` only for
  `(.busy, true, true)`, `.generic` for the other ten. In particular assert that
  `(.available, true, true)` is `.generic`, which is the case a reasonable
  person would get wrong.
- `PlateFaceParityTests`: a table-driven test whose expected values are
  transcribed from `effectiveDisplayState` in `viewer/src/lib/freshness.ts`. If
  the viewer's logic changes, this is what fails.
- `ReasonLineTests`: all thirteen rows of §6.4, in precedence order, including the
  cases where two conditions are true at once and the earlier row must win.
- `RelativeTimeTests`: the boundaries at 10s, 60s, and 60m.
- `SourceStateTests`: `unknown` and `sourceAbsent` both map to
  `Can't tell`, never to `No call`. Fail-closed, asserted.

### 16.3 Automated checks

Add to CI:

- **String literals.** Extend the existing grep to
  `mac-app/Packages/MPUI/Sources/`. Any string literal in a view file that is
  not a symbol name, an asset name, or a scene ID fails the build.
- **Deck parity.** Every `Strings.*` case has a matching row in
  `docs/copy/deck.md`, and every row in the deck's Owner app section has a
  matching case. Both directions.
- **Banned words.** Grep the §12.5 list, including em dashes, across
  `Strings.swift` and `docs/copy/deck.md`.
- **Contrast.** Compute the WCAG ratio for each pair in §4.1's table and assert
  it meets the stated minimum. This catches a colour tweak that a human would
  wave through.
- **Payload parity.** Assert that `StatusPayload` has exactly five encodable
  properties and that `get_paired_status()` returns exactly seven keys.

  Then assert the Privacy section's columns are **five, four, and seven** rows.
  The counts deliberately do not line up with the two numbers above, so read
  them carefully before changing anything. The left column is five because it
  covers the payload's five fields, except that `screenSharing` is always `nil`
  and is not listed, and the display name is listed even though it travels on
  the device record rather than in the payload. The middle column is four
  because three of the RPC's seven keys (`paired`, `server_now`,
  `schema_version`) are plumbing the reader has no use for. The right column is
  seven things that never leave the Mac and correspond to no field anywhere.

  Any new payload field or projection key fails this test and
  forces a conversation before it can ship. The Supabase side of this already
  exists in `supabase/tests/05_viewer_read.sql`; extend it rather than writing a
  second assertion.
- **`screenSharing` stays nil.** Assert that every `StatusPayload` constructed
  in the app target passes `screenSharing: nil`. The field is plumbed all the
  way to the database and populating it would silently widen the boundary that
  §7.4 describes.

### 16.4 By hand, before you call it done

1. Fresh install, no local secret file. Onboarding through to a working link.
2. Deny Accessibility, then grant it while the app is running. The banner and
   the row must both resolve without a relaunch.
3. Join a Google Meet. The plate hoists a cone within one check interval.
4. Set busy for 15 minutes. Watch the countdown roll and reach zero.
5. Turn off Wi-Fi for a minute. The rail says `No network. Waiting.` and
   recovers on its own.
6. Run the same account on a second Mac. This one shows the superseded banner
   and stops publishing.
7. Toggle Reduce Motion. Walk every screen. Nothing animates, everything still
   changes.
8. Toggle to light appearance. Walk every screen.
9. Set the largest Accessibility text size. Walk every screen. Nothing clips.
10. Greyscale screenshot of each section. Every state still readable.
11. Delete everything. Confirm the terminal state, then quit and relaunch.

---

## 17. Risks and open decisions

### 17.1 API availability

Deployment target is macOS 14.0 (`MACOSX_DEPLOYMENT_TARGET = 14.0`), Xcode 16.2,
Swift 6.0.

**Do not use without a gate.** Every one of these is macOS 15+, and this plan is
written so none is needed:

`ContainerBackgroundPlacement.window` (so `.containerBackground(_:for: .window)`),
`.windowLevel`, `.restorationBehavior`, `.windowBackgroundDragBehavior`,
`.defaultLaunchBehavior`, `WindowStyle.plain`, `UtilityWindow`,
`Color.mix(with:by:)`, `MeshGradient`, `.pointerStyle`, `.searchFocused`,
`.toolbar(removing:)`, and the symbol effects `.wiggle`, `.breathe`, `.rotate`.

macOS 26 only: `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
`ToolbarSpacer`, `backgroundExtensionEffect`. Not in scope.

If you ever do need one, note that **scene modifiers cannot take an inline
`if #available`**. The workaround is an extension that branches internally:

```swift
extension Scene {
  func mpWindowLevelFloating() -> some Scene {
    if #available(macOS 15, *) { return windowLevel(.floating) }
    else { return self }
  }
}
```

**Safe at 14.0, used by this plan:** `Window`, `MenuBarExtra`,
`.menuBarExtraStyle`, `.defaultSize`, `.defaultPosition`,
`.windowResizability`, `NavigationSplitView`,
`.navigationSplitViewColumnWidth`, `.listStyle(.sidebar)`, `Section(isExpanded:)`,
`ContentUnavailableView`, `Form` + `.formStyle(.grouped)`, `LabeledContent`,
`ShareLink`, `.buttonStyle(.accessoryBar)`, `.onKeyPress`,
`NSApplication.activate()`, `SMAppService.openSystemSettingsLoginItems()`,
`withAnimation(_:completionCriteria:_:completion:)`, `.spring(duration:bounce:)`,
`.smooth`/`.snappy`/`.bouncy`, `PhaseAnimator`, `.keyframeAnimator`,
`.visualEffect`, `.geometryGroup()`, `.contentTransition(.symbolEffect(.replace))`,
`.symbolEffect(.bounce/.pulse/.scale/.variableColor)`,
`.clipShape(.rect(cornerRadius:))`. `.contentTransition(.numericText(countsDown:))`
is macOS 13.

**A documentation caveat worth knowing.** Apple's live developer site is
generated from a current SDK and back-dates some WWDC23 symbols; `.smooth`, for
example, displays as macOS 10.15. Treat every WWDC23 animation API as macOS
14+ regardless of what the page says, and let the compiler be the authority.

### 17.2 `.hoverEffect` does not exist on macOS

It is iOS, tvOS, and visionOS only. Every hover state in this plan uses
`.onHover { }` plus `withAnimation(MPMotion.quick)`. If you find yourself
writing `.hoverEffect`, the file will not compile, and reaching for
`#if os(iOS)` to fix it means you are in the wrong file.

### 17.3 Menu bar animation is unverified

§9.4 and V3. The label lives in an `NSStatusItem`, not a normal SwiftUI window,
and nothing in the documentation promises that `.animation` works there.
Budget for it not working. An icon that swaps instantly is completely
acceptable; a timer-driven `NSImage` frame sequence in the menu bar is not, and
would undo the battery argument in §10.1.

### 17.4 Open decision: Archivo

`DESIGN.md` says the world uses Archivo 400 and 600, bundled locally.
`viewer/src/styles/global.css` lists `'Archivo'` first in its stack, but there
is no `@font-face` rule anywhere and `viewer/public/` contains no font files.
The viewer therefore renders in `-apple-system` today.

This plan ships the system font, so the Mac app matches what she actually sees.
That is the right call now and it needs no work.

The open question is for someone else: either bundle Archivo in both surfaces,
or update `DESIGN.md` to describe the system stack. Leaving `DESIGN.md`
describing a font nothing loads is the only outcome that is wrong. File it; do
not fix it inside this work.

### 17.5 Scope pressure

Three things will look tempting during the build. All three are out of scope,
and doing any of them makes this change unreviewable.

- Refactoring `StatusReducer` while wiring `EffectiveStatus.reason` through.
- Adding a detection source because the Watch section makes the gap visible.
- Adding a field to `StatusPayload` because the UI could show something useful.
  This one is a privacy regression, and §16.3's payload parity test exists
  specifically to stop it.

### 17.6 The mast is the whole risk

`MPCore.State` has three cases and the viewer's board has four faces, and the
mapping between them is neither obvious nor one to one. Three ways to get it
wrong, in descending order of likelihood:

1. Mapping `State` to `PlateFace` one to one and giving `available` a green
   plate. The owner then sees a confident "Available" board while his wife's
   page reads `Meeting status unavailable`.
2. Treating calls-are-okay as a decoration on the busy face rather than as its
   own face with its own shape, plate, and headline.
3. Drawing the pennant as the mast plus a flag. The viewer draws a bare pole
   plus a flag, with no yard.

`PlateFace.init(state:callsOkay:isFresh:)` in §6.2 is a line-for-line port of
`effectiveDisplayState`, and the parity test in §16.2 exists to keep it one.
Write those two first, before any view.

---

## 18. Definition of done

Not done until every line is true.

**Function**

- [ ] Every capability in §2.1 is reachable at its stated location.
- [ ] The menu bar has exactly six items plus two submenus.
- [ ] All ten wirings in §11.4 are live, W3's heartbeat included.
- [ ] All six defects in §1.3 are fixed.
- [ ] `StatusPayload` is byte-identical to `main`, `screenSharing` included.

**Craft**

- [ ] No view file contains a raw colour, duration, radius, or spacing number.
- [ ] Every component in §4.7 ships all seven states.
- [ ] Every view file has at least three previews using `PreviewStore`.
- [ ] All twenty motion items in §10.2 behave as specified.
- [ ] Every animation is instant under Reduce Motion, and every state change
      still happens.
- [ ] No load choreography anywhere except M09 and M18.
- [ ] No continuous idle animation anywhere, above all in the menu bar.

**Copy**

- [ ] Every user-facing string comes from `Strings.swift`.
- [ ] `Strings.swift` and `docs/copy/deck.md` agree in both directions.
- [ ] No banned word from §12.5 appears anywhere, em dashes included.
- [ ] No two error paths share a message.

**Accessibility**

- [ ] Every contrast pair in §4.1 measured and passing.
- [ ] Greyscale screenshots of all four sections readable.
- [ ] VoiceOver walk complete; the plate reads as one element.
- [ ] Full Keyboard Access reaches every control in the §13.4 order.
- [ ] Nothing clips at the largest Accessibility text size.

**Verification**

- [ ] V1 through V5 run, with results recorded.
- [ ] All §16.2 unit tests pass.
- [ ] All §16.3 CI checks pass, payload parity included.
- [ ] All eleven manual passes in §16.4 done.

**Documentation**

- [ ] The direction contract from §3 is the header of `StationWindow.swift`.
- [ ] `DESIGN.md` has an owner-app section describing what was built.
- [ ] A decision record exists for the menu bar icon change, for the
      two-register mast, and for every verification that failed.

Unreviewed and undocumented is unfinished.
