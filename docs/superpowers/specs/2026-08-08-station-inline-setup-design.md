# Station-first inline setup

**Date:** 2026-08-08
**Status:** Design selected for implementation

## Summary

Meeting Pulse will stop opening an onboarding window. The existing Station
window becomes the first-run home and shows a focused setup checklist in the
Watch detail. The checklist uses the selected "Signal checklist" direction:
one short introduction followed by three numbered rows for Accessibility,
the private viewer link, and the always-on menu bar watcher.

Accessibility changes will be reflected without restarting the app. The
permission monitor will check at a short interval, the launch coordinator will
forward a trust change to the running detection runtime, and the runtime will
invalidate its detector snapshots and request an immediate sample.

## Goals

- Make Station the only first-run entry surface.
- Keep setup in the same place as the live status instead of in a modal flow.
- Move from Accessibility settings to a live detector state without a relaunch.
- Preserve the privacy copy and existing setup persistence behavior.
- Keep the existing Station shell, marine enamel palette, and native macOS
  controls.
- Make Accessibility loss visible and recoverable after setup.

## Non-goals

- Redesigning the Sharing, This Mac, Privacy, pairing, recovery, or diagnostics
  windows.
- Changing the detector rules or the fail-closed status reducer.
- Adding a new dependency or a custom window/chrome treatment.
- Removing the old onboarding source files in this change. They will no longer
  be reachable from the normal application flow, but remain to avoid an
  unrelated cleanup deletion.

## Experience

### First launch

1. The menu bar launch path opens `station` and selects Watch when setup is
   incomplete or a setup error is present.
2. While Accessibility is not granted, the Watch detail renders the inline
   checklist instead of the normal Watch groups.
3. The checklist headline is "Let's get your signal online." The supporting
   copy explains that window titles are read locally and call contents are
   never read.
4. Row 1 shows Accessibility. Its status is driven by
   `store.accessibilityGranted`, and its action opens System Settings.
5. When trust becomes true, the checklist is replaced immediately by the live
   Watch groups and the detector starts sampling. No Continue button or
   relaunch is required.
6. While setup is still incomplete, Watch shows one compact inline prompt to
   create the private viewer link or open Sharing. The user can also create the
   link from the checklist before granting Accessibility.
7. "Do this later" and successful link creation complete setup persistence. The
   checklist's final row explains that the menu bar keeps watching and is
   visible before the live Watch transition.

Existing users continue to use the persisted `setup.completed` value. Users
who defer link creation can still create it later from Sharing.

### After setup

The normal Watch detail remains the source of truth for permission, detector
sources, and publishing. If Accessibility is revoked, the existing permission
banner is shown again and its action opens System Settings. The app does not
reopen an onboarding window; a launch with missing permission opens Station so
the repair path is visible.

The delete-completed empty state will no longer route to onboarding. Its
recovery action will quit the app, matching the existing copy that asks the
owner to quit before setting it up again. The onboarding scene remains
unreachable from the regular first-run and recovery paths.

## Visual system

The checklist is a native SwiftUI detail view, not a modal or a stack of
generic cards:

- Keep the Station sidebar and Mast visible as the persistent status anchor.
- Use one focused heading, one supporting sentence, and three numbered rows.
- Separate rows with hairlines and use the existing brass accent only for the
  active permission action and checked state.
- Keep the existing `MPColor`, `MPFont`, `MPSpace`, and `MPRadius` tokens.
- Use a restrained opacity/content transition for status changes. Respect
  `accessibilityReduceMotion`.
- Keep buttons native, keyboard reachable, and visibly focused.

## Permission refresh design

`PermissionCoordinator` will expose an explicit current-value refresh in
addition to its stream and will use a one-second poll interval. The check is a
single `AXIsProcessTrusted()` query and is intentionally kept lightweight so
that the app does not depend on a relaunch or on a System Settings callback.

`AppLaunchCoordinator` will consume the stream as it does today, but each
trust change will:

1. Update `PulseStore.accessibilityGranted`.
2. Ask the existing `OwnerRuntime` to request an immediate scheduler sample.
3. Let `DetectionScheduler.tick()` observe the new trust value, invalidate both
   source detectors, reset their settlers, and emit a fresh reading.

The existing fail-closed reducer remains authoritative while the first trusted
sample is pending. The sidebar may show the permission row as granted before
the first sample arrives, but the status headline will not claim availability
until the reducer receives a valid reading.

## Implementation boundaries

Expected changes:

- `mac-app/MeetingPulse/MeetingPulseApp.swift`
  - open Station for incomplete setup or missing permission;
  - forward permission changes to the runtime;
  - remove the normal onboarding-window route from launch behavior.
- `mac-app/MeetingPulse/AppPulseActions.swift`
  - complete setup when link creation succeeds;
  - keep the existing defer action;
  - make the delete-completed recovery action quit instead of opening onboarding.
- `mac-app/Packages/MPUI/Sources/MPUI/Station/StationWindow.swift`
  - route the Watch detail to the checklist while setup is incomplete.
- `mac-app/Packages/MPUI/Sources/MPUI/Sections/WatchSection.swift`
  - render the checklist and preserve the existing Watch groups after setup.
- `mac-app/Packages/MPUI/Sources/MPUI/Components/MPSetupChecklist.swift`
  - new focused checklist component using the existing UI tokens.
- `mac-app/Packages/MPSupport/Sources/MPSupport/PermissionCoordinator.swift`
  - add current-value refresh support and use the short poll cadence.
- `mac-app/Packages/MPUI/Tests/MPUITests/`
  - cover setup row state and completion behavior.
- `mac-app/Packages/MPSupport/Tests/`
  - cover permission refresh stream behavior through the coordinator's injected
    `@Sendable` trust provider.

No production files are deleted as part of this change.

## Error handling and resilience

- A failed viewer-link request keeps the checklist visible and uses the
  existing `PulseError.createLink` state.
- A permission query that remains false keeps the row actionable and the
  status unavailable; it never falls through to an Available state.
- A trust change that occurs before the runtime is ready is retained in the
  store, and the scheduler's initial start reads the current trust value.
- A trust change after runtime startup triggers an immediate sample, avoiding
  the normal idle polling delay.
- Existing setup/configuration failures remain inline in Watch and do not open
  a modal.

## Validation

- Unit-test the checklist's permission and completion state transitions.
- Unit-test the permission monitor's refresh/change path with an injected
  `@Sendable` trust provider.
- Run the existing MPUI, MPSupport, and MPDetection test targets.
- Run the existing local macOS build and repository lint target.
- Use the MPUI visual review target to inspect the setup, dark/light, and
  increased-contrast states.
