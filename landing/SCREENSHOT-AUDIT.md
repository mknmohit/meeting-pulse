# Product screenshot audit

The landing site contains 21 light/dark screenshot pairs. Each pair was
reviewed for product relevance, readability at responsive widths, privacy
safety, and whether it adds information beyond another capture.

## Use on the public marketing site

| Pair | Where it is used | Why |
| --- | --- | --- |
| `meeting-pulse-diagnostics-window` | Features, troubleshooting | Shows detector health without exposing private meeting content. |
| `meeting-pulse-onboarding-window` | How it works, install docs | Clear first-run context at a wide, low-height aspect ratio. |
| `meeting-pulse-recovery-window` | Recovery docs | Explains recovery without revealing a recovery phrase. |
| `meeting-pulse-station-privacy` | Homepage, privacy | Direct privacy surface with the owner-side boundary visible. |
| `meeting-pulse-station-sharing` | Homepage, pairing docs | Shows where a viewer link begins. |
| `meeting-pulse-station-sharing-viewers` | Homepage workflow | Shows owner control over paired viewers. |
| `meeting-pulse-station-watch-available` | How it works | Makes the automatic watch state legible. |
| `meeting-pulse-station-watch-call-okay` | Features | Directly supports the manual status and Call okay explanation. |
| `meeting-pulse-station-watch-meeting` | Homepage hero, workflow | Strongest owner-side proof of the core meeting state. |
| `meeting-pulse-station-watch-permission` | Accessibility docs | Directly shows the permission state and its explanation. |
| `meeting-pulse-viewer-call-okay` | Homepage, workflow | Shows the viewer’s positive call-okay state. |
| `meeting-pulse-viewer-meeting-named` | Homepage workflow | Shows the viewer’s primary in-meeting state. |
| `meeting-pulse-viewer-offline` | Homepage workflow | Makes a disconnected state visible without relying on color alone. |
| `meeting-pulse-viewer-pairing` | Features | Shows the browser-side pairing surface. |
| `meeting-pulse-viewer-status-unavailable` | How it works | Shows the fail-closed unavailable state. |

## Intentionally ignored or held back

| Pair | Decision | Reason |
| --- | --- | --- |
| `meeting-pulse-menu-bar` | Ignore for now | The crop is small and less legible than the Station captures at landing-page widths. |
| `meeting-pulse-pairing-window` | Ignore for now | It repeats the pairing story with a placeholder code; the viewer pairing capture is clearer. |
| `meeting-pulse-recovery-window-revealed` | Never use publicly | It displays a recovery phrase. Even though it is sample data, it teaches the wrong sharing behavior. |
| `meeting-pulse-station-setup` | Hold | It overlaps with onboarding and privacy captures without adding a clearer marketing moment. |
| `meeting-pulse-station-this-mac` | Hold | It is a broad control surface; the Call okay capture is more specific for the feature page. |
| `meeting-pulse-viewer-couple-mode` | Hold | Couple mode is not part of the current public positioning and should not be implied as a primary product promise. |

Every pair listed as used has both `-light.jpg` and `-dark.jpg` variants. The
shared screenshot component switches the actual image source when the selected
theme changes; explicit Light/Dark choices therefore override the OS preference
without letting a `<picture>` media source reselect the wrong variant.
